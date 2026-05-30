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

test("updateAlertStatus 可把 new 改成 acknowledged，並補 acknowledgedAt", async () => {
  const filePath = tempFile();
  const saved = await store.saveAlert(base, { filePath });
  assert.equal(saved.alert.status, "new");

  const r = await store.updateAlertStatus(saved.alert.id, "acknowledged", { filePath });
  assert.equal(r.success, true);
  assert.equal(r.alert.status, "acknowledged");
  assert.ok(r.alert.acknowledgedAt, "應有 acknowledgedAt");
  assert.ok(r.alert.statusUpdatedAt, "應有 statusUpdatedAt");
  // 保留原欄位
  assert.equal(r.alert.riskLevel, "urgent");
  assert.equal(r.alert.id, saved.alert.id);
});

test("updateAlertStatus 可把 acknowledged 改成 resolved，並補 resolvedAt", async () => {
  const filePath = tempFile();
  const saved = await store.saveAlert(base, { filePath });
  await store.updateAlertStatus(saved.alert.id, "acknowledged", { filePath });
  const r = await store.updateAlertStatus(saved.alert.id, "resolved", { filePath });
  assert.equal(r.success, true);
  assert.equal(r.alert.status, "resolved");
  assert.ok(r.alert.resolvedAt, "應有 resolvedAt");
  // 先前的 acknowledgedAt 應被保留
  assert.ok(r.alert.acknowledgedAt, "應保留 acknowledgedAt");
});

test("updateAlertStatus 不合法 status 回 invalid_status（且不寫檔）", async () => {
  const filePath = tempFile();
  const saved = await store.saveAlert(base, { filePath });
  const r = await store.updateAlertStatus(saved.alert.id, "bogus", { filePath });
  assert.deepEqual(r, { success: false, error: "invalid_status" });
});

test("updateAlertStatus 找不到 id 回 not_found", async () => {
  const filePath = tempFile();
  await store.saveAlert(base, { filePath });
  const r = await store.updateAlertStatus("does-not-exist", "acknowledged", { filePath });
  assert.deepEqual(r, { success: false, error: "not_found" });
});

test("updateAlertStatus 後 listAlerts 可看到新 status", async () => {
  const filePath = tempFile();
  const saved = await store.saveAlert(base, { filePath });
  await store.updateAlertStatus(saved.alert.id, "resolved", { filePath });
  const list = await store.listAlerts({ filePath });
  assert.equal(list.length, 1);
  assert.equal(list[0].status, "resolved");
  // 也可用 status 篩選查到
  const resolved = await store.listAlerts({ filePath, status: "resolved" });
  assert.equal(resolved.length, 1);
});

test("updateAlertStatus 後 getAlertById 可看到新 status", async () => {
  const filePath = tempFile();
  const saved = await store.saveAlert(base, { filePath });
  await store.updateAlertStatus(saved.alert.id, "acknowledged", { filePath });
  const got = await store.getAlertById(saved.alert.id, { filePath });
  assert.ok(got);
  assert.equal(got.status, "acknowledged");
  assert.ok(got.acknowledgedAt);
});

// ---- CR-0002 Batch 2：四級正規化與向下相容 ----

test("normalizeRiskLevel 規則：legacy→權威、原樣保留、未知→low", () => {
  assert.equal(store.normalizeRiskLevel("normal"), "low");
  assert.equal(store.normalizeRiskLevel("attention"), "medium");
  assert.equal(store.normalizeRiskLevel("urgent"), "urgent");
  assert.equal(store.normalizeRiskLevel("low"), "low");
  assert.equal(store.normalizeRiskLevel("medium"), "medium");
  assert.equal(store.normalizeRiskLevel("high"), "high");
  // 未知 / 空 / null → low
  assert.equal(store.normalizeRiskLevel("bogus"), "low");
  assert.equal(store.normalizeRiskLevel(""), "low");
  assert.equal(store.normalizeRiskLevel(null), "low");
  assert.equal(store.normalizeRiskLevel(undefined), "low");
  // 大小寫 / 空白不敏感
  assert.equal(store.normalizeRiskLevel(" Attention "), "medium");
  assert.equal(store.normalizeRiskLevel("URGENT"), "urgent");
});

test("saveAlert 寫入前正規化 riskLevel（normal→low、attention→medium、high 原樣）", async () => {
  const filePath = tempFile();
  const a = await store.saveAlert({ ...base, riskLevel: "normal" }, { filePath });
  const b = await store.saveAlert({ ...base, riskLevel: "attention" }, { filePath });
  const c = await store.saveAlert({ ...base, riskLevel: "high" }, { filePath });
  assert.equal(a.alert.riskLevel, "low");
  assert.equal(b.alert.riskLevel, "medium");
  assert.equal(c.alert.riskLevel, "high");
});

test("filter 用新值可命中由舊代碼寫入的資料（attention 查 medium）", async () => {
  const filePath = tempFile();
  await store.saveAlert({ ...base, riskLevel: "attention" }, { filePath });
  await store.saveAlert({ ...base, riskLevel: "urgent" }, { filePath });
  const medium = await store.listAlerts({ filePath, riskLevel: "medium" });
  assert.equal(medium.length, 1);
  assert.equal(medium[0].riskLevel, "medium");
});

test("filter 用舊代碼也能命中（查 attention 命中已正規化的 medium）", async () => {
  const filePath = tempFile();
  await store.saveAlert({ ...base, riskLevel: "attention" }, { filePath });
  const byLegacy = await store.listAlerts({ filePath, riskLevel: "attention" });
  assert.equal(byLegacy.length, 1);
});

test("filter 對未被正規化的舊 care_alerts.json 仍正確（讀時比對也 normalize）", async () => {
  // 模擬一份「Batch 2 之前就寫好、未正規化」的 care_alerts.json。
  const filePath = tempFile();
  const legacy = [
    {
      id: "legacy-1",
      receivedAt: "2026-05-20T10:00:00.000Z",
      status: "new",
      riskLevel: "attention",
      riskLevelLabel: "需注意",
      category: "loneliness",
      triggerSummary: "舊資料",
      transcriptSnippet: "片段",
      createdAt: "2026-05-20T10:00:00.000",
      source: "companion_analysis",
    },
    {
      id: "legacy-2",
      receivedAt: "2026-05-20T11:00:00.000Z",
      status: "new",
      riskLevel: "normal",
      riskLevelLabel: "一般",
      category: "other",
      triggerSummary: "舊資料2",
      transcriptSnippet: "片段2",
      createdAt: "2026-05-20T11:00:00.000",
      source: "companion_analysis",
    },
  ];
  fs.writeFileSync(filePath, JSON.stringify(legacy, null, 2), "utf8");

  // 舊資料原樣保留（讀取不改寫），但 filter 用權威值仍可命中。
  const all = await store.listAlerts({ filePath });
  assert.equal(all.length, 2);
  const medium = await store.listAlerts({ filePath, riskLevel: "medium" });
  assert.equal(medium.length, 1);
  assert.equal(medium[0].id, "legacy-1");
  assert.equal(medium[0].riskLevel, "attention", "讀取不改寫舊資料本身");
  const low = await store.listAlerts({ filePath, riskLevel: "low" });
  assert.equal(low.length, 1);
  assert.equal(low[0].id, "legacy-2");
});

// ---- CR-0008：Care Alert 綁 elderId（向下相容）----

test("saveAlert 寫入 elderId；未帶入為 null", async () => {
  const filePath = tempFile();
  const withElder = await store.saveAlert(
    { ...base, elderId: "elder-1" },
    { filePath },
  );
  assert.equal(withElder.alert.elderId, "elder-1");
  const withoutElder = await store.saveAlert(base, { filePath });
  assert.equal(withoutElder.alert.elderId, null, "未帶入應為 null");
});

test("listAlerts elderId 過濾：明確帶入才過濾", async () => {
  const filePath = tempFile();
  await store.saveAlert({ ...base, elderId: "elder-1" }, { filePath });
  await store.saveAlert({ ...base, elderId: "elder-2" }, { filePath });
  await store.saveAlert(base, { filePath }); // elderId=null

  const e1 = await store.listAlerts({ filePath, elderId: "elder-1" });
  assert.equal(e1.length, 1);
  assert.equal(e1[0].elderId, "elder-1");

  // 未帶 elderId → 回全部（含 null）。
  const all = await store.listAlerts({ filePath });
  assert.equal(all.length, 3);
});

test("listAlerts elderId 過濾：舊資料缺 elderId 欄位視為 null，不被特定 elderId 命中", async () => {
  const filePath = tempFile();
  // 直接寫入一筆「沒有 elderId 欄位」的舊資料。
  const fsSync = require("node:fs");
  fsSync.writeFileSync(
    filePath,
    JSON.stringify([
      {
        id: "legacy-no-elder",
        riskLevel: "urgent",
        status: "new",
        receivedAt: "2026-05-20T00:00:00.000Z",
      },
    ]),
    "utf8",
  );
  await store.saveAlert({ ...base, elderId: "elder-1" }, { filePath });

  // 帶 elder-1 → 只命中新資料，不含舊缺欄位資料。
  const e1 = await store.listAlerts({ filePath, elderId: "elder-1" });
  assert.equal(e1.length, 1);
  assert.equal(e1[0].elderId, "elder-1");

  // 未帶 elderId → 兩筆都回（含缺欄位舊資料）。
  const all = await store.listAlerts({ filePath });
  assert.equal(all.length, 2);
});
