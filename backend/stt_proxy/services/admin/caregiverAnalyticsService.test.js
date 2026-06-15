const assert = require("node:assert/strict");
const { test } = require("node:test");

// CR-0086：caregiverAnalyticsService 聚合邏輯單元測試（無 DB，直接注入資料）。
// 驗證：Care Alert 分桶 / 高風險比例 / 今日 + 區間計數 / rangeDays 夾值 /
// 任務完成率 + 簽到 proxy / 情緒 + 遊戲誠實標註（insufficient 不捏造）。

const svc = require("./caregiverAnalyticsService");

const NOW = "2026-06-15T12:00:00.000Z";
function daysAgo(n) {
  const d = new Date("2026-06-15T12:00:00.000Z");
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString();
}

test("clampRangeDays：非法 / 超界 → 夾在 1..90，預設 7", () => {
  assert.equal(svc.clampRangeDays(undefined), 7);
  assert.equal(svc.clampRangeDays("abc"), 7);
  assert.equal(svc.clampRangeDays(0), 1);
  assert.equal(svc.clampRangeDays(-5), 1);
  assert.equal(svc.clampRangeDays(14), 14);
  assert.equal(svc.clampRangeDays(9999), 90);
});

test("Care Alert 分桶 / 高風險比例 / 今日 + 區間計數正確", async () => {
  const alerts = [
    { riskLevel: "urgent", receivedAt: NOW }, // 今日 + 區間
    { riskLevel: "high", receivedAt: daysAgo(2) }, // 區間
    { riskLevel: "medium", receivedAt: daysAgo(5) }, // 區間
    { riskLevel: "low", receivedAt: daysAgo(20) }, // 區間外（7 天）
  ];
  const out = await svc.buildResidentAnalytics("elder-1", {
    rangeDays: 7,
    nowIso: NOW,
    alerts,
    tasks: [],
    analysis: null,
  });

  assert.equal(out.careAlertStats.urgent, 1);
  assert.equal(out.careAlertStats.high, 1);
  assert.equal(out.careAlertStats.medium, 1);
  assert.equal(out.careAlertStats.low, 0); // 20 天前那筆不在 7 天區間
  assert.equal(out.careAlertStats.total, 3);
  assert.equal(out.careAlertStats.highRiskRatio, 2 / 3);
  assert.equal(out.summary.todayAlertCount, 1);
  assert.equal(out.summary.rangeAlertCount, 3);
  // 最近一筆 alert 的風險（陣列首筆）。
  assert.equal(out.summary.latestRiskLevel, "urgent");
});

test("rangeDays=30 會把 20 天前那筆納入", async () => {
  const alerts = [{ riskLevel: "low", receivedAt: daysAgo(20) }];
  const out = await svc.buildResidentAnalytics("elder-1", {
    rangeDays: 30,
    nowIso: NOW,
    alerts,
    tasks: [],
    analysis: null,
  });
  assert.equal(out.careAlertStats.low, 1);
  assert.equal(out.careAlertStats.total, 1);
  assert.equal(out.rangeDays, 30);
});

test("任務完成率 / 依類型分組 / 簽到 proxy", async () => {
  const tasks = [
    { type: "medication", status: "completed", latestSubmission: { submittedAt: NOW } },
    { type: "medication", status: "pending", latestSubmission: null },
    { type: "hydration", status: "completed", latestSubmission: { submittedAt: daysAgo(1) } },
    { type: "exercise", status: "missed", latestSubmission: null },
  ];
  const out = await svc.buildResidentAnalytics("elder-1", {
    nowIso: NOW,
    alerts: [],
    tasks,
    analysis: null,
  });

  assert.equal(out.taskStats.total, 4);
  assert.equal(out.taskStats.completed, 2);
  assert.equal(out.taskStats.completionRate, 0.5);
  assert.deepEqual(out.taskStats.byType.medication, { completed: 1, total: 2 });
  assert.deepEqual(out.taskStats.byType.hydration, { completed: 1, total: 1 });
  assert.deepEqual(out.taskStats.byType.exercise, { completed: 0, total: 1 });
  // 今日有提交（medication）→ 簽到 completed。
  assert.equal(out.taskStats.checkInStatus, "completed");
  assert.equal(out.taskStats.lastCheckInAt, NOW);
  assert.equal(out.summary.taskCompletionRate, 0.5);
});

test("無資料：空狀態不崩潰、不捏造（careAlert 0 / task none / 情緒 + 遊戲 insufficient / 寵物空）", async () => {
  const out = await svc.buildResidentAnalytics("elder-empty", {
    nowIso: NOW,
    alerts: [],
    tasks: [],
    analysis: null,
  });

  assert.equal(out.careAlertStats.total, 0);
  assert.equal(out.careAlertStats.highRiskRatio, 0);
  assert.equal(out.careAlertStats.lastAlertAt, null);
  assert.equal(out.taskStats.total, 0);
  assert.equal(out.taskStats.completionRate, null);
  assert.equal(out.taskStats.checkInStatus, "none");
  assert.deepEqual(out.emotionTrend, []);
  assert.equal(out.emotionDataSource, "insufficient");
  assert.equal(out.summary.latestEmotion, null);
  assert.equal(out.gameMetrics.hasEnoughData, false);
  assert.equal(out.gameMetrics.message, "目前尚無足夠遊戲紀錄");
  assert.equal(out.petStatus.available, false);
  assert.equal(out.summary.latestRiskLevel, null);
});

test("情緒趨勢沿用 analysis：reference 序列轉成 {date,emotion,score}，latestEmotion 取最後一筆", async () => {
  const analysis = {
    emotionHistory: [
      { date: "2026-06-13", emotion: "平穩", score: 0.6 },
      { date: "2026-06-14", emotion: "低落", score: 0.4 },
    ],
    emotionDataSource: "reference",
    gameMetrics: { series: [{ date: "2026-06-14" }], trend: "declining", abnormal: true, dataSource: "reference" },
  };
  const out = await svc.buildResidentAnalytics("seed-1", {
    nowIso: NOW,
    alerts: [],
    tasks: [],
    analysis,
  });
  assert.equal(out.emotionTrend.length, 2);
  assert.deepEqual(out.emotionTrend[0], { date: "2026-06-13", emotion: "平穩", score: 0.6 });
  assert.equal(out.emotionDataSource, "reference");
  assert.equal(out.summary.latestEmotion, "低落");
  assert.equal(out.gameMetrics.hasEnoughData, true);
  assert.equal(out.gameMetrics.dataSource, "reference");
  assert.equal(out.gameMetrics.abnormal, true);
});
