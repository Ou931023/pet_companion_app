const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const store = require("./careAlertStoreService");

function tempFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_unit_"));
  return path.join(dir, "care_alerts.json");
}

const base = {
  riskLevel: "urgent",
  riskLevelLabel: "緊急",
  category: "other",
  categoryLabel: "其他",
  triggerSummary: "對話中偵測到需要關心的狀況",
  transcriptSnippet: "我昨天晚上都睡不好",
  createdAt: "2026-05-29T10:00:00.000Z",
  source: "companion_analysis",
};

test("saveAlert 補上 id / receivedAt / status:new，並可被 list 查到", async () => {
  const filePath = tempFile();
  const r = await store.saveAlert(base, { filePath });
  assert.equal(r.success, true);
  assert.ok(r.alert.id, "應自動產生 id");
  assert.ok(r.alert.receivedAt, "應有 receivedAt");
  assert.equal(r.alert.status, "new");
  assert.equal(r.alert.riskLevel, "urgent");
  assert.equal(r.alert.transcriptSnippet, "我昨天晚上都睡不好");

  const list = await store.listAlerts({ filePath });
  assert.equal(list.length, 1);
  assert.equal(list[0].id, r.alert.id);
});

test("listAlerts 預設新到舊排序", async () => {
  const filePath = tempFile();
  await store.saveAlert({ ...base, triggerSummary: "第一" }, { filePath });
  await store.saveAlert({ ...base, triggerSummary: "第二" }, { filePath });
  await store.saveAlert({ ...base, triggerSummary: "第三" }, { filePath });
  const list = await store.listAlerts({ filePath });
  assert.deepEqual(
    list.map((a) => a.triggerSummary),
    ["第三", "第二", "第一"],
  );
});

test("listAlerts riskLevel 篩選正確", async () => {
  const filePath = tempFile();
  await store.saveAlert({ ...base, riskLevel: "urgent" }, { filePath });
  await store.saveAlert({ ...base, riskLevel: "attention" }, { filePath });
  await store.saveAlert({ ...base, riskLevel: "urgent" }, { filePath });
  const urgent = await store.listAlerts({ filePath, riskLevel: "urgent" });
  assert.equal(urgent.length, 2);
  assert.ok(urgent.every((a) => a.riskLevel === "urgent"));
});

test("listAlerts status 篩選正確", async () => {
  const filePath = tempFile();
  await store.saveAlert(base, { filePath });
  await store.saveAlert({ ...base, status: "resolved" }, { filePath });
  const news = await store.listAlerts({ filePath, status: "new" });
  assert.equal(news.length, 1);
  assert.equal(news[0].status, "new");
  const resolved = await store.listAlerts({ filePath, status: "resolved" });
  assert.equal(resolved.length, 1);
  assert.equal(resolved[0].status, "resolved");
});

test("listAlerts limit 生效", async () => {
  const filePath = tempFile();
  for (let i = 0; i < 5; i++) {
    await store.saveAlert({ ...base, triggerSummary: `s${i}` }, { filePath });
  }
  const list = await store.listAlerts({ filePath, limit: 2 });
  assert.equal(list.length, 2);
});

test("getAlertById 找得到 / 找不到回 null", async () => {
  const filePath = tempFile();
  const r = await store.saveAlert(base, { filePath });
  const found = await store.getAlertById(r.alert.id, { filePath });
  assert.ok(found);
  assert.equal(found.id, r.alert.id);

  const missing = await store.getAlertById("does-not-exist", { filePath });
  assert.equal(missing, null);
});

test("讀取不存在的檔案視為空清單，不丟例外", async () => {
  const filePath = tempFile(); // 尚未寫入任何資料
  const list = await store.listAlerts({ filePath });
  assert.deepEqual(list, []);
  const missing = await store.getAlertById("x", { filePath });
  assert.equal(missing, null);
});
