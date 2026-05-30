// CR-0007 Batch 2：健康後台分析服務單元測試（node --test，不需 .env / 不需真 DB）。
//
// 涵蓋：
//   - overview 六指標計算
//   - 個人分析聚合形狀
//   - physio / emotion / game 序列確定性（同 elderId 兩次呼叫結果相同）
//   - 情緒異常 / 遊戲退化判定規則
//   - 未知 elderId → null（endpoint 轉 404）

const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const service = require("./adminAnalysisService");
const healthMetrics = require("./healthMetrics");
const { createRng } = require("./deterministic");

// 寫一份 temp elders.json，注入固定長者清單，避免依賴 DB 或正式 data。
function writeEldersFile(elders) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "admin_elders_"));
  const file = path.join(dir, "elders.json");
  fs.writeFileSync(file, JSON.stringify(elders, null, 2), "utf8");
  return file;
}

function writeUsersFile(users) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "admin_users_"));
  const file = path.join(dir, "users.json");
  fs.writeFileSync(file, JSON.stringify(users, null, 2), "utf8");
  return file;
}

function emptyCareAlertsFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "admin_alerts_"));
  return path.join(dir, "care_alerts.json");
}

const ELDERS = [
  { id: "elder-a", display_name: "陳奶奶", birth_year: 1948, gender: "female" },
  { id: "elder-b", display_name: "林爺爺", birth_year: 1945, gender: "male" },
];

function baseOptions() {
  return {
    eldersFilePath: writeEldersFile(ELDERS),
    usersFilePath: writeUsersFile([]),
    careAlertsFilePath: emptyCareAlertsFile(),
  };
}

test("physio 序列對同一 elderId 兩次呼叫結果完全相同（確定性）", () => {
  const a = healthMetrics.getPhysio("elder-a");
  const b = healthMetrics.getPhysio("elder-a");
  assert.deepEqual(a, b);
  // 不同 elderId 應產生不同序列。
  const c = healthMetrics.getPhysio("elder-b");
  assert.notDeepEqual(a.series, c.series);
});

test("physio 數值落在合理區間", () => {
  const { series } = healthMetrics.getPhysio("elder-a");
  for (const day of series) {
    assert.ok(day.reminderCompletionRate >= 0 && day.reminderCompletionRate <= 1);
    assert.ok(day.medicationCompletionRate >= 0 && day.medicationCompletionRate <= 1);
    assert.ok(day.dailyInteractionMinutes >= 5 && day.dailyInteractionMinutes <= 60);
    assert.ok(day.sleepHours >= 4 && day.sleepHours <= 9);
    assert.ok(typeof day.sleepQuality === "string" && day.sleepQuality.length > 0);
  }
});

test("emotion 序列確定性且 analyze 判定穩定", () => {
  const a = healthMetrics.getEmotion("elder-a");
  const b = healthMetrics.getEmotion("elder-a");
  assert.deepEqual(a, b);
  assert.ok(typeof a.abnormal === "boolean");
  assert.ok(typeof a.dominantEmotion === "string");
});

test("game 序列確定性，且 trend/abnormal 一致", () => {
  const a = healthMetrics.getGameMetrics("elder-a");
  const b = healthMetrics.getGameMetrics("elder-a");
  assert.deepEqual(a, b);
  assert.ok(["stable", "declining"].includes(a.trend));
  assert.equal(a.abnormal, a.trend === "declining");
  for (const day of a.series) {
    assert.ok(day.cognitiveScore >= 0 && day.cognitiveScore <= 100);
    assert.ok(day.completionRate >= 0 && day.completionRate <= 1);
  }
});

test("情緒異常判定規則：近 7 日負向占比 > 0.5 → abnormal", () => {
  // 構造一組近 7 日多數負向的序列，驗判定規則。
  const series = [
    { date: "2026-05-25", emotion: "孤單", score: 0.2, summary: "" },
    { date: "2026-05-26", emotion: "低落", score: 0.3, summary: "" },
    { date: "2026-05-27", emotion: "焦慮", score: 0.25, summary: "" },
    { date: "2026-05-28", emotion: "煩躁", score: 0.2, summary: "" },
    { date: "2026-05-29", emotion: "平靜", score: 0.7, summary: "" },
    { date: "2026-05-30", emotion: "開心", score: 0.8, summary: "" },
    { date: "2026-05-31", emotion: "孤單", score: 0.2, summary: "" },
  ];
  const result = healthMetrics.analyzeEmotion(series);
  assert.equal(result.abnormal, true); // 5/7 負向 > 0.5
});

test("情緒正常判定：多數正向 → 不 abnormal", () => {
  const series = [
    { date: "2026-05-25", emotion: "平靜", score: 0.7, summary: "" },
    { date: "2026-05-26", emotion: "開心", score: 0.8, summary: "" },
    { date: "2026-05-27", emotion: "放鬆", score: 0.75, summary: "" },
    { date: "2026-05-28", emotion: "滿足", score: 0.85, summary: "" },
    { date: "2026-05-29", emotion: "孤單", score: 0.3, summary: "" },
    { date: "2026-05-30", emotion: "開心", score: 0.8, summary: "" },
    { date: "2026-05-31", emotion: "平靜", score: 0.7, summary: "" },
  ];
  const result = healthMetrics.analyzeEmotion(series);
  assert.equal(result.abnormal, false);
});

test("遊戲退化判定規則：後半段明顯下降且最近 < 基線 → declining", () => {
  const series = [
    { cognitiveScore: 80 },
    { cognitiveScore: 78 },
    { cognitiveScore: 76 },
    { cognitiveScore: 74 },
    { cognitiveScore: 60 },
    { cognitiveScore: 58 },
    { cognitiveScore: 55 },
    { cognitiveScore: 52 },
  ];
  const result = healthMetrics.analyzeGame(series);
  assert.equal(result.trend, "declining");
  assert.equal(result.abnormal, true);
});

test("遊戲穩定判定：分數平穩 → stable", () => {
  const series = [
    { cognitiveScore: 70 },
    { cognitiveScore: 72 },
    { cognitiveScore: 69 },
    { cognitiveScore: 71 },
    { cognitiveScore: 70 },
    { cognitiveScore: 73 },
    { cognitiveScore: 68 },
    { cognitiveScore: 71 },
  ];
  const result = healthMetrics.analyzeGame(series);
  assert.equal(result.trend, "stable");
  assert.equal(result.abnormal, false);
});

test("overview 六指標形狀與計算（無真實 care alert 時的基本值）", async () => {
  const options = baseOptions();
  const overview = await service.getOverview(options);
  assert.equal(overview.totalElders, 2);
  for (const key of [
    "totalElders",
    "activeToday",
    "careAlertsToday",
    "highRiskElders",
    "emotionAbnormalElders",
    "cognitiveDeclineElders",
  ]) {
    assert.ok(Number.isInteger(overview[key]), `${key} 應為整數`);
  }
  // 無 care alert → careAlertsToday / highRiskElders 為 0。
  assert.equal(overview.careAlertsToday, 0);
  assert.equal(overview.highRiskElders, 0);
});

test("overview 反映真實 care alert（高風險 + 今日）", async () => {
  const careAlertsFilePath = emptyCareAlertsFile();
  const careAlertStore = require("../careAlertStoreService");
  const todayIso = new Date().toISOString();
  await careAlertStore.saveAlert(
    {
      elderId: "elder-a",
      riskLevel: "urgent",
      triggerSummary: "需要關心",
      transcriptSnippet: "片段",
      createdAt: todayIso,
    },
    { filePath: careAlertsFilePath },
  );
  const options = {
    eldersFilePath: writeEldersFile(ELDERS),
    usersFilePath: writeUsersFile([]),
    careAlertsFilePath,
    todayIso,
  };
  const overview = await service.getOverview(options);
  assert.equal(overview.careAlertsToday, 1);
  assert.equal(overview.highRiskElders, 1);
});

test("listElderSummaries 回每位長者一列且欄位齊全", async () => {
  const options = baseOptions();
  const rows = await service.listElderSummaries(options);
  assert.equal(rows.length, 2);
  for (const row of rows) {
    for (const key of [
      "elderId",
      "displayName",
      "lastActiveAt",
      "latestRiskLevel",
      "emotionAbnormal",
      "cognitiveDecline",
    ]) {
      assert.ok(key in row, `缺欄位 ${key}`);
    }
  }
});

test("getElderAnalysis 個人完整分析形狀正確", async () => {
  const options = baseOptions();
  const analysis = await service.getElderAnalysis("elder-a", options);
  assert.ok(analysis);
  assert.equal(analysis.profile.elderId, "elder-a");
  assert.equal(analysis.profile.displayName, "陳奶奶");
  assert.ok(Array.isArray(analysis.careAlerts));
  assert.ok(Array.isArray(analysis.emotionHistory));
  assert.ok(analysis.physio.series.length > 0);
  assert.ok(typeof analysis.psych.summary === "string");
  assert.ok(["stable", "declining"].includes(analysis.gameMetrics.trend));
});

test("未知 elderId → 個人分析回 null", async () => {
  const options = baseOptions();
  assert.equal(await service.getElderAnalysis("nobody", options), null);
  assert.equal(await service.getElderPhysio("nobody", options), null);
  assert.equal(await service.getElderEmotion("nobody", options), null);
  assert.equal(await service.getElderGameMetrics("nobody", options), null);
});

test("elders 來源為空時回示範長者種子（Dashboard 不為空）", async () => {
  const options = {
    eldersFilePath: writeEldersFile([]),
    usersFilePath: writeUsersFile([]),
    careAlertsFilePath: emptyCareAlertsFile(),
  };
  const rows = await service.listElderSummaries(options);
  assert.ok(rows.length >= 6, "至少 6 位示範長者");
  // 對外可見「值」不得出現工程字樣（只檢查 values，不檢查契約欄位名，
  // 例如 latestRiskLevel 這個 §11 規定的 key 含 "test" 子字串屬正常）。
  const values = rows.flatMap((r) => Object.values(r)).map((v) => String(v));
  const blob = values.join(" ").toLowerCase();
  for (const banned of ["demo", "fake", "mock", "debug"]) {
    assert.ok(!blob.includes(banned), `列表值不得出現工程字樣：${banned}`);
  }
});

test("確定性 PRNG：同 seed 同序列、不同 seed 不同序列", () => {
  const r1 = createRng("seed-x");
  const r2 = createRng("seed-x");
  const r3 = createRng("seed-y");
  const s1 = [r1(), r1(), r1()];
  const s2 = [r2(), r2(), r2()];
  const s3 = [r3(), r3(), r3()];
  assert.deepEqual(s1, s2);
  assert.notDeepEqual(s1, s3);
  for (const v of s1) {
    assert.ok(v >= 0 && v < 1);
  }
});
