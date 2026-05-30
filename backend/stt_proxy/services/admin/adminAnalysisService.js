// 健康後台分析聚合服務（CR-0007 Batch 2）。
//
// 契約見 PROJECT_ARCHITECTURE.md §11。
// 真實資料優先：
//   - elders / users → eldersSource（DB 優先、fallback data/elders.json，無資料時回示範種子）。
//   - care alert → careAlertStoreService.listAlerts({ elderId })（真實警示，CR-0008 過濾）。
// 生理 / 情緒 / 遊戲指標 → 確定性產生器（healthMetrics，不串智慧手環、可重現）。
//
// 對外可見值保持乾淨：不得出現 demo / fake / mock / test / debug 等工程字樣。

const eldersSource = require("./eldersSource");
const healthMetrics = require("./healthMetrics");
const careAlertStore = require("../careAlertStoreService");

// 高風險判定：權威 riskLevel 為 high / urgent。
const HIGH_RISK_LEVELS = new Set(["high", "urgent"]);

function isToday(iso, anchorIso) {
  if (!iso) return false;
  const day = String(iso).slice(0, 10);
  const anchorDay = (anchorIso || new Date().toISOString()).slice(0, 10);
  return day === anchorDay;
}

// 取某長者的真實 care alert（依 elderId 過濾）。
async function careAlertsForElder(elderId, options = {}) {
  try {
    return await careAlertStore.listAlerts({
      elderId,
      filePath: options.careAlertsFilePath,
    });
  } catch (_) {
    return [];
  }
}

// 計算單一長者的摘要列（給 /elders 與 /overview 使用）。
async function summarizeElder(elder, options = {}) {
  const alerts = await careAlertsForElder(elder.id, options);
  const emotion = healthMetrics.getEmotion(elder.id, options);
  const game = healthMetrics.getGameMetrics(elder.id, options);
  const physio = healthMetrics.getPhysio(elder.id, options);

  // 最近一筆 care alert 的風險（新到舊已排序，取第一筆）；無則回 null。
  const latestRiskLevel = alerts.length ? alerts[0].riskLevel : null;

  // 最近活動時間：以最近 care alert 或生理序列最後一天推估。
  const lastPhysioDate = physio.series.length
    ? physio.series[physio.series.length - 1].date
    : null;
  const lastActiveAt = alerts.length
    ? alerts[0].receivedAt || alerts[0].createdAt || lastPhysioDate
    : lastPhysioDate;

  return {
    elder,
    alerts,
    emotion,
    game,
    physio,
    summaryRow: {
      elderId: elder.id,
      displayName: elder.displayName,
      lastActiveAt,
      latestRiskLevel,
      emotionAbnormal: emotion.abnormal,
      cognitiveDecline: game.abnormal,
    },
  };
}

// GET /api/admin/overview → 六指標。
async function getOverview(options = {}) {
  const elders = await eldersSource.listElders(options);
  const anchorIso = options.todayIso;

  let activeToday = 0;
  let careAlertsToday = 0;
  let highRiskElders = 0;
  let emotionAbnormalElders = 0;
  let cognitiveDeclineElders = 0;

  for (const elder of elders) {
    const s = await summarizeElder(elder, options);
    const todaysAlerts = s.alerts.filter((a) =>
      isToday(a.receivedAt || a.createdAt, anchorIso),
    );
    careAlertsToday += todaysAlerts.length;
    if (s.summaryRow.lastActiveAt && isToday(s.summaryRow.lastActiveAt, anchorIso)) {
      activeToday += 1;
    }
    if (
      s.summaryRow.latestRiskLevel &&
      HIGH_RISK_LEVELS.has(s.summaryRow.latestRiskLevel)
    ) {
      highRiskElders += 1;
    }
    if (s.summaryRow.emotionAbnormal) emotionAbnormalElders += 1;
    if (s.summaryRow.cognitiveDecline) cognitiveDeclineElders += 1;
  }

  return {
    totalElders: elders.length,
    activeToday,
    careAlertsToday,
    highRiskElders,
    emotionAbnormalElders,
    cognitiveDeclineElders,
  };
}

// GET /api/admin/elders → 長者列表（摘要列）。
async function listElderSummaries(options = {}) {
  const elders = await eldersSource.listElders(options);
  const rows = [];
  for (const elder of elders) {
    const s = await summarizeElder(elder, options);
    rows.push(s.summaryRow);
  }
  return rows;
}

// GET /api/admin/elders/:elderId → 個人完整分析。找不到回 null（endpoint 轉 404）。
async function getElderAnalysis(elderId, options = {}) {
  const elder = await eldersSource.getElder(elderId, options);
  if (!elder) return null;

  const alerts = await careAlertsForElder(elderId, options);
  const physio = healthMetrics.getPhysio(elderId, options);
  const psych = healthMetrics.buildPsych(elderId, options);
  const emotion = healthMetrics.getEmotion(elderId, options);
  const game = healthMetrics.getGameMetrics(elderId, options);

  return {
    profile: {
      elderId: elder.id,
      displayName: elder.displayName,
      birthYear: elder.birthYear,
      gender: elder.gender,
      bindingStatus: elder.bindingStatus,
    },
    careAlerts: alerts,
    physio,
    psych,
    emotionHistory: emotion.series,
    gameMetrics: game,
  };
}

// 以下三個對應各 sub-route；找不到長者回 null。
async function getElderPhysio(elderId, options = {}) {
  const elder = await eldersSource.getElder(elderId, options);
  if (!elder) return null;
  return healthMetrics.getPhysio(elderId, options);
}

async function getElderEmotion(elderId, options = {}) {
  const elder = await eldersSource.getElder(elderId, options);
  if (!elder) return null;
  return healthMetrics.getEmotion(elderId, options);
}

async function getElderGameMetrics(elderId, options = {}) {
  const elder = await eldersSource.getElder(elderId, options);
  if (!elder) return null;
  return healthMetrics.getGameMetrics(elderId, options);
}

module.exports = {
  getOverview,
  listElderSummaries,
  getElderAnalysis,
  getElderPhysio,
  getElderEmotion,
  getElderGameMetrics,
};
