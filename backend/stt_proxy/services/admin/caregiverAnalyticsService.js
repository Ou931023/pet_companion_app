// CR-0086：長照管理端「長者狀態分析」聚合服務。
//
// 把單一長者近期的「真實營運訊號」整理成一份分析摘要，供 caregiver_web 分析頁與
// GET /api/caregiver/analytics 使用。授權（caregiver 只能看授權住民、super_admin 看全部）
// 由 route 層的 resolveAdminAuthContext + authorizationService 負責，本服務只做聚合，
// 不做身分判斷。
//
// 誠實原則（不可捏造）：
//   - Care Alert 統計、今日 / 區間警示數、最近風險等級 → 來自真實 care_alerts。
//   - 任務 / 簽到 → 來自真實 daily_care_tasks（+ submissions）；目前無獨立「簽到」資料表，
//     簽到狀態以「當日是否有任務證明提交」推估，並於文件 (CR0086) 標明來源。
//   - 情緒趨勢 / 遊戲退化 → 沿用 adminAnalysisService 的資料真實性標註
//     （measured / reference / insufficient）。真實長者目前無真實情緒 / 遊戲寫入流程，
//     會回 insufficient（前端顯示「資料不足」），不捏造數據。
//   - App 使用 / 寵物互動 → 來自真實 app_usage_events；沒有上報時回資料不足。
//
// 可測試性：核心資料（alerts / tasks / analysis）可由 options 直接注入，
// 不注入時才走真實 store；故聚合邏輯可在無 DB 環境單元測試。

const defaultCareAlertStore = require("../careAlertStoreService");
const defaultDailyCareTaskStore = require("../dailyCareTask/dailyCareTaskStore");
const defaultAdminAnalysis = require("./adminAnalysisService");
const defaultAppUsageStore = require("../appUsageEventStore");

const RISK_LEVELS = ["low", "medium", "high", "urgent"];
const HIGH_RISK_LEVELS = new Set(["high", "urgent"]);
const DONE_TASK_STATUS = "completed";
const TASK_TYPES = ["medication", "hydration", "exercise"];

const DEFAULT_RANGE_DAYS = 7;
const MIN_RANGE_DAYS = 1;
const MAX_RANGE_DAYS = 90;

// rangeDays 防呆：非數字 / 超界 → 預設 7，並夾在 1..90。
function clampRangeDays(value) {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n)) return DEFAULT_RANGE_DAYS;
  if (n < MIN_RANGE_DAYS) return MIN_RANGE_DAYS;
  if (n > MAX_RANGE_DAYS) return MAX_RANGE_DAYS;
  return n;
}

function dayKey(iso) {
  return iso ? String(iso).slice(0, 10) : null;
}

// alert 的時間戳：以 receivedAt 為主，缺則 createdAt。
function alertTime(alert) {
  return (alert && (alert.receivedAt || alert.createdAt)) || null;
}

// 是否落在 [now - rangeDays, now] 區間內（以日期字串比較，含當日）。
function withinRange(iso, nowIso, rangeDays) {
  const day = dayKey(iso);
  if (!day) return false;
  const end = new Date(dayKey(nowIso) + "T00:00:00.000Z");
  const start = new Date(end.getTime() - (rangeDays - 1) * 24 * 60 * 60 * 1000);
  const d = new Date(day + "T00:00:00.000Z");
  return d >= start && d <= end;
}

async function safeListAlerts(elderId, store, options) {
  try {
    const alerts = await store.listAlerts({
      elderId,
      filePath: options.careAlertsFilePath,
      pg: options.pg,
    });
    return Array.isArray(alerts) ? alerts : [];
  } catch (_error) {
    return [];
  }
}

async function safeListTasks(elderId, store, options) {
  try {
    const tasks = await store.listTasksForAdmin({
      elderId,
      tasksFilePath: options.tasksFilePath,
      submissionsFilePath: options.submissionsFilePath,
      pg: options.pg,
    });
    return Array.isArray(tasks) ? tasks : [];
  } catch (_error) {
    return [];
  }
}

async function safeElderAnalysis(elderId, analysis, options) {
  try {
    return await analysis.getElderAnalysis(elderId, options);
  } catch (_error) {
    return null;
  }
}

async function safeUsageStats(elderId, store, options) {
  try {
    return await store.getUsageStats(elderId, {
      rangeDays: options.rangeDays,
      nowIso: options.nowIso,
      pg: options.pg,
      eventsFilePath: options.eventsFilePath,
      events: options.usageEvents,
    });
  } catch (_error) {
    return {
      available: false,
      totalEvents: 0,
      activeDays: 0,
      totalDurationMs: 0,
      lastEventAt: null,
      byType: {},
    };
  }
}

// Care Alert 統計：依風險等級分桶 + 高風險比例 + 最近一次警示時間。
function buildCareAlertStats(alertsInRange) {
  const stats = { low: 0, medium: 0, high: 0, urgent: 0, total: 0 };
  let lastAlertAt = null;
  let highRisk = 0;
  for (const alert of alertsInRange) {
    const level = RISK_LEVELS.includes(alert.riskLevel) ? alert.riskLevel : "low";
    stats[level] += 1;
    stats.total += 1;
    if (HIGH_RISK_LEVELS.has(level)) highRisk += 1;
    const t = alertTime(alert);
    if (t && (!lastAlertAt || String(t) > String(lastAlertAt))) lastAlertAt = t;
  }
  stats.highRiskRatio = stats.total ? highRisk / stats.total : 0;
  stats.lastAlertAt = lastAlertAt;
  return stats;
}

// 任務 / 簽到統計：完成率、依類型分組、簽到（以當日是否有提交推估）。
function buildTaskStats(tasks, nowIso) {
  const total = tasks.length;
  let completed = 0;
  let pending = 0;
  let lastCheckInAt = null;
  let checkedInToday = false;
  const byType = {};
  for (const type of TASK_TYPES) {
    byType[type] = { completed: 0, total: 0 };
  }
  const today = dayKey(nowIso);

  for (const task of tasks) {
    if (!task) continue;
    const done = task.status === DONE_TASK_STATUS;
    if (done) completed += 1;
    else pending += 1;

    if (byType[task.type]) {
      byType[task.type].total += 1;
      if (done) byType[task.type].completed += 1;
    }

    const submittedAt =
      task.latestSubmission && task.latestSubmission.submittedAt
        ? task.latestSubmission.submittedAt
        : null;
    if (submittedAt) {
      if (!lastCheckInAt || String(submittedAt) > String(lastCheckInAt)) {
        lastCheckInAt = submittedAt;
      }
      if (dayKey(submittedAt) === today) checkedInToday = true;
    }
  }

  return {
    completed,
    pending,
    total,
    completionRate: total ? completed / total : null,
    byType,
    // 無獨立簽到表：以「當日是否有任務證明提交」作為簽到 proxy（見 CR0086 文件）。
    checkInStatus: total === 0 ? "none" : checkedInToday ? "completed" : "pending",
    lastCheckInAt,
  };
}

// 情緒趨勢：沿用 adminAnalysisService 的 emotionHistory + dataSource（誠實標註）。
function buildEmotionTrend(analysis) {
  if (!analysis || !Array.isArray(analysis.emotionHistory)) {
    return { emotionTrend: [], emotionDataSource: "insufficient", latestEmotion: null };
  }
  const trend = analysis.emotionHistory.map((item) => ({
    date: item && (item.date || item.day) ? item.date || item.day : null,
    emotion:
      item && (item.emotion || item.label || item.mood)
        ? item.emotion || item.label || item.mood
        : null,
    score:
      item && (item.score != null || item.confidence != null)
        ? item.score != null
          ? item.score
          : item.confidence
        : null,
  }));
  const latest = trend.length ? trend[trend.length - 1].emotion : null;
  return {
    emotionTrend: trend,
    emotionDataSource: analysis.emotionDataSource || "insufficient",
    latestEmotion: latest,
  };
}

// 遊戲退化指標：沿用 adminAnalysisService.gameMetrics 的 dataSource；資料不足回友善訊息。
function buildGameMetrics(analysis) {
  const game = analysis && analysis.gameMetrics ? analysis.gameMetrics : null;
  const dataSource = game && game.dataSource ? game.dataSource : "insufficient";
  const series = game && Array.isArray(game.series) ? game.series : [];
  const hasEnoughData = dataSource !== "insufficient" && series.length > 0;
  return {
    hasEnoughData,
    dataSource,
    trend: game && game.trend ? game.trend : "stable",
    abnormal: !!(game && game.abnormal),
    series,
    message: hasEnoughData ? null : "目前尚無足夠遊戲紀錄",
  };
}

// 寵物照護狀態：來自 app_usage_events 的真實寵物互動 / 外觀偏好事件。
function buildPetStatus(usageStats) {
  if (usageStats && usageStats.available) {
    const meta = usageStats.latestPetMetadata || {};
    return {
      available: true,
      mood: meta.mood || null,
      satiety: meta.satiety == null ? null : meta.satiety,
      intimacy: meta.intimacy == null ? null : meta.intimacy,
      petType: meta.petType || meta.petStyle || null,
      lastInteractionAt: usageStats.lastEventAt,
      interactionCount: usageStats.petInteractions || 0,
      message: null,
    };
  }
  return {
    available: false,
    mood: null,
    satiety: null,
    intimacy: null,
    petType: null,
    lastInteractionAt: null,
    message: "目前尚無寵物互動上報資料",
  };
}

// 主入口：彙整單一長者的分析資料。
// options：
//   - rangeDays：天數（預設 7，夾 1..90）
//   - nowIso：時間錨點（測試可注入；預設現在）
//   - alerts / tasks / analysis：可直接注入資料（單元測試用），不注入才走真實 store
//   - careAlertStore / dailyCareTaskStore / adminAnalysis / appUsageStore：可替換的依賴
//   - careAlertsFilePath / tasksFilePath / submissionsFilePath / pg：傳給 store 的測試 seam
async function buildResidentAnalytics(elderId, options = {}) {
  const rangeDays = clampRangeDays(options.rangeDays);
  const nowIso = options.nowIso || new Date().toISOString();
  const careAlertStore = options.careAlertStore || defaultCareAlertStore;
  const dailyCareTaskStore = options.dailyCareTaskStore || defaultDailyCareTaskStore;
  const adminAnalysis = options.adminAnalysis || defaultAdminAnalysis;
  const appUsageStore = options.appUsageStore || defaultAppUsageStore;

  const alerts = Array.isArray(options.alerts)
    ? options.alerts
    : await safeListAlerts(elderId, careAlertStore, options);
  const tasks = Array.isArray(options.tasks)
    ? options.tasks
    : await safeListTasks(elderId, dailyCareTaskStore, options);
  const analysis =
    options.analysis !== undefined
      ? options.analysis
      : await safeElderAnalysis(elderId, adminAnalysis, options);
  const usageStats = await safeUsageStats(elderId, appUsageStore, {
    ...options,
    rangeDays,
    nowIso,
  });

  const alertsInRange = alerts.filter((a) =>
    withinRange(alertTime(a), nowIso, rangeDays),
  );
  const todayAlertCount = alerts.filter(
    (a) => dayKey(alertTime(a)) === dayKey(nowIso),
  ).length;

  const careAlertStats = buildCareAlertStats(alertsInRange);
  const taskStats = buildTaskStats(tasks, nowIso);
  const emotion = buildEmotionTrend(analysis);
  const gameMetrics = buildGameMetrics(analysis);
  const petStatus = buildPetStatus(usageStats);

  // 最近一次互動：取最近 app usage、警示與任務提交中較新的一個。
  const latestAlertAt = careAlertStats.lastAlertAt || (alerts.length ? alertTime(alerts[0]) : null);
  const lastInteractionAt =
    [usageStats.lastEventAt, latestAlertAt, taskStats.lastCheckInAt]
      .filter(Boolean)
      .sort((a, b) => String(b).localeCompare(String(a)))[0] || null;

  const latestRiskLevel = alerts.length ? alerts[0].riskLevel : null;

  return {
    elderId,
    rangeDays,
    generatedAt: nowIso,
    summary: {
      todayAlertCount,
      rangeAlertCount: careAlertStats.total,
      taskCompletionRate: taskStats.completionRate,
      latestEmotion: emotion.latestEmotion,
      latestRiskLevel,
      lastInteractionAt,
    },
    emotionTrend: emotion.emotionTrend,
    emotionDataSource: emotion.emotionDataSource,
    careAlertStats,
    taskStats,
    usageStats,
    gameMetrics,
    petStatus,
  };
}

module.exports = {
  buildResidentAnalytics,
  // 測試 / 工具用：暴露純函式與常數。
  clampRangeDays,
  buildCareAlertStats,
  buildTaskStats,
  buildPetStatus,
  withinRange,
  DEFAULT_RANGE_DAYS,
  MAX_RANGE_DAYS,
};
