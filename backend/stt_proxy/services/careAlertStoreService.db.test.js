// CR-P2A Batch 2/3：careAlertStoreService DB 路徑單測（mock pg，不需實連 DB）。
//
// 驗：5 函式 DB 路徑的 SQL / 欄位映射、狀態軌跡 append、回傳形狀與 JSON 一致、
// DB 例外 → 降級 JSON（不丟例外、/notify 不失敗）、log 不外洩敏感資料。

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const store = require("./careAlertStoreService");

function tempFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_db_"));
  return path.join(dir, "care_alerts.json");
}

// mock pg：available 控制 isPostgresAvailable；rowsFor 可為固定 rows 或
// (text,params)=>rows；throwOn(text) 回 true 時該次 query 拋例外（模擬 DB 故障）。
function makeMockPg({ available = true, rowsFor = [], throwOn = null } = {}) {
  const calls = [];
  return {
    calls,
    isPostgresAvailable: async () => available,
    query: async (text, params) => {
      calls.push({ text, params });
      if (throwOn && throwOn(text, params)) {
        throw new Error("mock db failure");
      }
      const rows = typeof rowsFor === "function" ? rowsFor(text, params) : rowsFor;
      return { rows: rows || [] };
    },
  };
}

const base = {
  elderId: "11111111-1111-1111-1111-111111111111",
  riskLevel: "urgent",
  riskLevelLabel: "緊急",
  category: "other",
  categoryLabel: "其他",
  triggerSummary: "對話中偵測到需要關心的狀況",
  transcriptSnippet: "我昨天晚上都睡不好",
  createdAt: "2026-05-29T10:00:00.000Z",
  source: "companion_analysis",
};

// ---- saveAlert（DB 路徑）----

test("saveAlert DB：INSERT 欄位映射正確、回傳形狀與 JSON 一致", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [] });
  const r = await store.saveAlert(base, { pg });

  assert.equal(r.success, true);
  assert.ok(r.alert.id, "應自動產生 id");
  assert.ok(r.alert.receivedAt, "應有 receivedAt");
  assert.equal(r.alert.status, "new");
  assert.equal(r.alert.riskLevel, "urgent");
  assert.equal(r.alert.elderId, base.elderId);
  assert.equal(r.alert.transcriptSnippet, "我昨天晚上都睡不好");
  // 回傳形狀（key 集合）需與 JSON 路徑 normalizeAlert 一致。
  assert.deepEqual(
    Object.keys(r.alert).sort(),
    Object.keys(store.normalizeAlert(base)).sort(),
  );

  // INSERT 參數映射
  assert.equal(pg.calls.length, 1);
  const { text, params } = pg.calls[0];
  assert.match(text, /INSERT INTO care_alerts/);
  assert.equal(params[0], r.alert.id); // id 由 service 端帶入
  assert.equal(params[1], base.elderId); // elder_id
  assert.equal(params[3], "new"); // status
  assert.equal(params[4], "urgent"); // risk_level
  assert.equal(params[5], "緊急"); // risk_level_label
  assert.equal(params[10], base.createdAt); // created_at
  assert.equal(params[11], "companion_analysis"); // source
});

test("saveAlert DB：寫入前正規化 riskLevel（attention→medium、normal→low）", async () => {
  const pg = makeMockPg({ available: true });
  const a = await store.saveAlert({ ...base, riskLevel: "attention" }, { pg });
  const b = await store.saveAlert({ ...base, riskLevel: "normal" }, { pg });
  assert.equal(a.alert.riskLevel, "medium");
  assert.equal(b.alert.riskLevel, "low");
  // 寫入 DB 的 risk_level 參數亦為四級
  assert.equal(pg.calls[0].params[4], "medium");
  assert.equal(pg.calls[1].params[4], "low");
});

test("saveAlert DB：空字串時間/文字欄位映射為 null（不寫空字串）", async () => {
  const pg = makeMockPg({ available: true });
  await store.saveAlert(
    { riskLevel: "high" }, // 其餘欄位缺 → normalizeAlert 給 ""
    { pg },
  );
  const { params } = pg.calls[0];
  assert.equal(params[5], null); // risk_level_label "" → null
  assert.equal(params[10], null); // created_at "" → null
  assert.equal(params[11], null); // source "" → null
});

test("saveAlert：DB 例外 → 降級 JSON，不丟例外、success:true", async () => {
  const filePath = tempFile();
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const r = await store.saveAlert(base, { pg, filePath });
  assert.equal(r.success, true, "DB 故障時應降級 JSON 並成功");
  // 確認真的寫進了 JSON 檔
  const onDisk = JSON.parse(fs.readFileSync(filePath, "utf8"));
  assert.equal(onDisk.length, 1);
  assert.equal(onDisk[0].id, r.alert.id);
});

// CR-0034 B2：production（ALLOW_JSON_FALLBACK=false）→ DB-required。
// DB 例外時**不得降級寫 JSON**，回 { success:false, error:'care_alert_persist_failed' }。
// 用 options.env 注入 production 語義（不依賴真實 NODE_ENV；NODE_ENV=test 仍恆為 dev）。
const prodEnv = { APP_ENV: "production" };

test("saveAlert：production DB 例外 → 不降級 JSON，回 care_alert_persist_failed", async () => {
  const filePath = tempFile();
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const r = await store.saveAlert(base, { pg, filePath, env: prodEnv });
  assert.deepEqual(r, { success: false, error: "care_alert_persist_failed" });
  // 確認**沒有**寫進 JSON 檔（檔案不存在或為空）。
  assert.equal(fs.existsSync(filePath), false, "production 不可降級寫 JSON");
});

test("saveAlert：production DB 不可用 → 直接回 care_alert_persist_failed（不寫 JSON）", async () => {
  const filePath = tempFile();
  const pg = makeMockPg({ available: false });
  const r = await store.saveAlert(base, { pg, filePath, env: prodEnv });
  assert.deepEqual(r, { success: false, error: "care_alert_persist_failed" });
  assert.equal(fs.existsSync(filePath), false);
});

test("updateAlertStatus：production DB 例外 → 不降級 JSON，回 care_alert_persist_failed", async () => {
  const filePath = tempFile();
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const r = await store.updateAlertStatus("some-id", "acknowledged", {
    pg,
    filePath,
    env: prodEnv,
  });
  assert.deepEqual(r, { success: false, error: "care_alert_persist_failed" });
});

test("saveAlert：dev DB 例外仍降級 JSON（production guard 不影響非 production）", async () => {
  const filePath = tempFile();
  const pg = makeMockPg({ available: true, throwOn: () => true });
  // 不帶 env → 走 process.env（NODE_ENV=test → development）→ 維持既有 fallback。
  const r = await store.saveAlert(base, { pg, filePath });
  assert.equal(r.success, true, "dev/staging 仍應降級 JSON");
  assert.equal(JSON.parse(fs.readFileSync(filePath, "utf8")).length, 1);
});

// ---- listAlerts（DB 路徑）----

test("listAlerts DB：WHERE/ORDER/LIMIT 組裝正確、row→alert 映射", async () => {
  const rows = [
    {
      id: "a-2",
      elder_id: base.elderId,
      received_at: new Date("2026-05-29T12:00:00.000Z"),
      status: "new",
      risk_level: "urgent",
      risk_level_label: "緊急",
      category: "other",
      category_label: "其他",
      trigger_summary: "後",
      transcript_snippet: "片段2",
      created_at: new Date("2026-05-29T10:00:00.000Z"),
      source: "companion_analysis",
      status_updated_at: null,
      acknowledged_at: null,
      resolved_at: null,
    },
  ];
  const pg = makeMockPg({ available: true, rowsFor: rows });
  const list = await store.listAlerts({
    pg,
    elderId: base.elderId,
    riskLevel: "urgent",
    status: "new",
    limit: 5,
  });

  assert.equal(list.length, 1);
  assert.equal(list[0].id, "a-2");
  assert.equal(list[0].receivedAt, "2026-05-29T12:00:00.000Z"); // Date→ISO
  assert.equal(list[0].createdAt, "2026-05-29T10:00:00.000Z");
  assert.equal(list[0].riskLevelLabel, "緊急");
  // 未更新狀態 → 不帶 statusUpdatedAt key（與 JSON 路徑一致）
  assert.ok(!("statusUpdatedAt" in list[0]));

  const { text, params } = pg.calls[0];
  assert.match(text, /SELECT \* FROM care_alerts/);
  assert.match(text, /elder_id = \$1/);
  assert.match(text, /risk_level = \$2/);
  assert.match(text, /status = \$3/);
  assert.match(text, /ORDER BY received_at DESC/);
  assert.match(text, /LIMIT \$4/);
  assert.equal(params[0], base.elderId);
  assert.equal(params[1], "urgent");
  assert.equal(params[2], "new");
  assert.equal(params[3], 5);
});

test("listAlerts DB：riskLevel 查詢值正規化（medium 查條件用 medium）", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [] });
  await store.listAlerts({ pg, riskLevel: "attention" });
  // attention → medium 後才進 SQL 參數
  assert.equal(pg.calls[0].params[0], "medium");
});

test("listAlerts DB：無 filter 時不帶 WHERE", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [] });
  await store.listAlerts({ pg });
  assert.doesNotMatch(pg.calls[0].text, /WHERE/);
});

test("listAlerts：DB 例外 → 降級 JSON", async () => {
  const filePath = tempFile();
  // 先用「不可用」把一筆寫進 JSON
  const jsonPg = makeMockPg({ available: false });
  await store.saveAlert(base, { pg: jsonPg, filePath });
  // DB 可用但 SELECT 故障 → 降級 JSON 讀回
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const list = await store.listAlerts({ pg, filePath });
  assert.equal(list.length, 1);
});

// ---- getAlertById（DB 路徑）----

test("getAlertById DB：找得到映射、找不到回 null", async () => {
  const row = {
    id: "got-1",
    elder_id: null,
    received_at: new Date("2026-05-29T12:00:00.000Z"),
    status: "acknowledged",
    risk_level: "high",
    risk_level_label: "需通知",
    category: null,
    category_label: null,
    trigger_summary: null,
    transcript_snippet: null,
    created_at: null,
    source: null,
    status_updated_at: new Date("2026-05-29T13:00:00.000Z"),
    acknowledged_at: new Date("2026-05-29T13:00:00.000Z"),
    resolved_at: null,
  };
  const found = makeMockPg({ available: true, rowsFor: [row] });
  const a = await store.getAlertById("got-1", { pg: found });
  assert.ok(a);
  assert.equal(a.id, "got-1");
  assert.equal(a.elderId, null);
  assert.equal(a.status, "acknowledged");
  assert.equal(a.createdAt, ""); // null → ""（與 JSON 形狀一致）
  assert.equal(a.acknowledgedAt, "2026-05-29T13:00:00.000Z");
  assert.ok(!("resolvedAt" in a)); // null 不帶 key
  assert.match(found.calls[0].text, /SELECT \* FROM care_alerts WHERE id = \$1/);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  const none = await store.getAlertById("nope", { pg: missing });
  assert.equal(none, null);
});

// ---- updateAlertStatus（DB 路徑 + 狀態軌跡）----

test("updateAlertStatus DB：UPDATE + append care_alert_status_events 軌跡", async () => {
  const updatedRow = {
    id: "u-1",
    elder_id: base.elderId,
    received_at: new Date("2026-05-29T12:00:00.000Z"),
    status: "acknowledged",
    risk_level: "urgent",
    risk_level_label: "緊急",
    category: "other",
    category_label: "其他",
    trigger_summary: "x",
    transcript_snippet: "y",
    created_at: null,
    source: "companion_analysis",
    status_updated_at: new Date("2026-05-29T14:00:00.000Z"),
    acknowledged_at: new Date("2026-05-29T14:00:00.000Z"),
    resolved_at: null,
    from_status: "new", // CTE RETURNING
  };
  const pg = makeMockPg({
    available: true,
    rowsFor: (text) =>
      /UPDATE care_alerts/.test(text) ? [updatedRow] : [],
  });

  const r = await store.updateAlertStatus("u-1", "acknowledged", {
    pg,
    actor: "caregiver_web",
  });
  assert.equal(r.success, true);
  assert.equal(r.alert.status, "acknowledged");
  assert.equal(r.alert.acknowledgedAt, "2026-05-29T14:00:00.000Z");
  assert.equal(r.alert.statusUpdatedAt, "2026-05-29T14:00:00.000Z");
  assert.equal(r.alert.riskLevel, "urgent");
  // from_status 不應外洩到對外 alert
  assert.ok(!("from_status" in r.alert));

  // 第 1 次 UPDATE（含 CTE 取 from_status），第 2 次 INSERT 軌跡
  assert.equal(pg.calls.length, 2);
  assert.match(pg.calls[0].text, /UPDATE care_alerts/);
  assert.match(pg.calls[0].text, /prev\.from_status/);
  const ev = pg.calls[1];
  assert.match(ev.text, /INSERT INTO care_alert_status_events/);
  assert.equal(ev.params[0], "u-1"); // alert_id
  assert.equal(ev.params[1], "new"); // from_status
  assert.equal(ev.params[2], "acknowledged"); // to_status
  assert.equal(ev.params[4], "caregiver_web"); // source/actor
});

test("updateAlertStatus DB：查無 id → not_found，不寫軌跡、不降級 JSON", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [] });
  const r = await store.updateAlertStatus("missing", "resolved", { pg });
  assert.deepEqual(r, { success: false, error: "not_found" });
  // 僅 UPDATE 一次，無軌跡 INSERT
  assert.equal(pg.calls.length, 1);
});

test("updateAlertStatus：不合法 status 回 invalid_status，不打 DB", async () => {
  const pg = makeMockPg({ available: true });
  const r = await store.updateAlertStatus("u-1", "bogus", { pg });
  assert.deepEqual(r, { success: false, error: "invalid_status" });
  assert.equal(pg.calls.length, 0);
});

test("updateAlertStatus DB：軌跡 INSERT 失敗仍回 success（best-effort）", async () => {
  const updatedRow = {
    id: "u-2",
    status: "resolved",
    risk_level: "high",
    received_at: new Date(),
    status_updated_at: new Date(),
    resolved_at: new Date(),
    from_status: "acknowledged",
  };
  const pg = makeMockPg({
    available: true,
    rowsFor: (text) => (/UPDATE care_alerts/.test(text) ? [updatedRow] : []),
    throwOn: (text) => /INSERT INTO care_alert_status_events/.test(text),
  });
  const r = await store.updateAlertStatus("u-2", "resolved", { pg });
  assert.equal(r.success, true);
  assert.equal(r.alert.status, "resolved");
});

test("updateAlertStatus：DB 例外（UPDATE 故障）→ 降級 JSON", async () => {
  const filePath = tempFile();
  const jsonPg = makeMockPg({ available: false });
  const saved = await store.saveAlert(base, { pg: jsonPg, filePath });
  // DB 可用但 UPDATE 故障 → 降級 JSON 更新
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const r = await store.updateAlertStatus(saved.alert.id, "acknowledged", {
    pg,
    filePath,
  });
  assert.equal(r.success, true);
  assert.equal(r.alert.status, "acknowledged");
});

// ---- deleteAlertsByElderId（DB 路徑）----

test("deleteAlertsByElderId DB：DELETE ... RETURNING 計數", async () => {
  const pg = makeMockPg({
    available: true,
    rowsFor: [{ id: "d1" }, { id: "d2" }],
  });
  const removed = await store.deleteAlertsByElderId(base.elderId, { pg });
  assert.equal(removed, 2);
  const { text, params } = pg.calls[0];
  assert.match(text, /DELETE FROM care_alerts WHERE elder_id = \$1/);
  assert.equal(params[0], base.elderId);
});

test("deleteAlertsByElderId：空 elderId 回 0，不打 DB", async () => {
  const pg = makeMockPg({ available: true });
  assert.equal(await store.deleteAlertsByElderId("", { pg }), 0);
  assert.equal(await store.deleteAlertsByElderId(null, { pg }), 0);
  assert.equal(pg.calls.length, 0);
});

test("deleteAlertsByElderId：DB 例外 → 降級 JSON", async () => {
  const filePath = tempFile();
  const jsonPg = makeMockPg({ available: false });
  await store.saveAlert(base, { pg: jsonPg, filePath });
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const removed = await store.deleteAlertsByElderId(base.elderId, {
    pg,
    filePath,
  });
  assert.equal(removed, 1);
});

// ---- 降級 / log 不外洩敏感 ----

test("DB 例外降級時 log 不含對話原文 / transcriptSnippet / PII", async () => {
  const filePath = tempFile();
  const original = console.error;
  const logged = [];
  console.error = (...args) => {
    logged.push(args.map((a) => JSON.stringify(a)).join(" "));
  };
  try {
    const pg = makeMockPg({ available: true, throwOn: () => true });
    await store.saveAlert(base, { pg, filePath });
  } finally {
    console.error = original;
  }
  const joined = logged.join("\n");
  assert.ok(joined.length > 0, "應有降級 log");
  assert.ok(
    !joined.includes(base.transcriptSnippet),
    "log 不得含 transcriptSnippet 原文",
  );
  assert.ok(!joined.includes(base.triggerSummary), "log 不得含 triggerSummary");
  assert.ok(!joined.includes(base.elderId), "log 不得含 elderId");
});
