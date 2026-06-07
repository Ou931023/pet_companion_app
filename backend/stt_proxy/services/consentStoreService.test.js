const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  recordConsent,
  getConsent,
  normalizeAction,
} = require("./consentStoreService");

// 建立記錄呼叫的 mock pool。rowsFor 可為固定 rows 或 (text,params)=>rows。
// throwError 設定時 query 會拋例外（模擬 DB 失敗）。
function makeMockPg(rowsFor, throwError) {
  const calls = [];
  return {
    calls,
    query: async (text, params) => {
      calls.push({ text, params });
      if (throwError) throw throwError;
      const rows = typeof rowsFor === "function" ? rowsFor(text, params) : rowsFor;
      return { rows: rows || [] };
    },
  };
}

test("normalizeAction：預設 granted、withdrawn 保留、未知轉 granted", () => {
  assert.equal(normalizeAction(undefined), "granted");
  assert.equal(normalizeAction("granted"), "granted");
  assert.equal(normalizeAction("withdrawn"), "withdrawn");
  assert.equal(normalizeAction("WITHDRAWN"), "withdrawn");
  assert.equal(normalizeAction("nonsense"), "granted");
});

test("recordConsent：INSERT 欄位映射正確、record 不含 PII", async () => {
  const agreed = new Date("2026-06-08T00:00:00.000Z");
  const pg = makeMockPg([
    {
      id: "rec-1",
      consent_type: "privacy_terms",
      consent_version: "1.0.0",
      action: "granted",
      agreed_at: agreed,
    },
  ]);

  const result = await recordConsent(
    {
      userId: "11111111-1111-1111-1111-111111111111",
      elderId: "22222222-2222-2222-2222-222222222222",
      firebaseUid: "uid-abc",
      consentType: "privacy_terms",
      consentVersion: "1.0.0",
      action: "granted",
      source: "elder_app_onboarding",
      appVersion: "1.2.3",
      platform: "ios",
      agreedAt: "2026-06-08T00:00:00.000Z",
      ip: "203.0.113.7",
      userAgent: "ElderApp/1.0",
    },
    { pg },
  );

  assert.equal(result.success, true);
  // record 形狀與 PII 遮蔽
  assert.deepEqual(Object.keys(result.record).sort(), [
    "action",
    "agreedAt",
    "consentType",
    "consentVersion",
    "id",
  ]);
  assert.equal(result.record.id, "rec-1");
  assert.equal(result.record.consentType, "privacy_terms");
  assert.equal(result.record.consentVersion, "1.0.0");
  assert.equal(result.record.action, "granted");
  // Date → ISO8601 字串
  assert.equal(result.record.agreedAt, "2026-06-08T00:00:00.000Z");
  assert.ok(!("ip" in result.record));
  assert.ok(!("userAgent" in result.record));

  // 參數映射（$1 userId, $2 elderId, $3 firebaseUid, $4 type, $5 version,
  //          $6 action, $7 source, $8 agreedAt, $9 appVersion, $10 platform,
  //          $11 ip, $12 userAgent）
  assert.equal(pg.calls.length, 1);
  const { text, params } = pg.calls[0];
  assert.match(text, /INSERT INTO consent_records/);
  assert.equal(params[0], "11111111-1111-1111-1111-111111111111");
  assert.equal(params[1], "22222222-2222-2222-2222-222222222222");
  assert.equal(params[2], "uid-abc");
  assert.equal(params[3], "privacy_terms");
  assert.equal(params[4], "1.0.0");
  assert.equal(params[5], "granted");
  assert.equal(params[6], "elder_app_onboarding");
  assert.equal(params[7], "2026-06-08T00:00:00.000Z");
  assert.equal(params[8], "1.2.3");
  assert.equal(params[9], "ios");
  assert.equal(params[10], "203.0.113.7");
  assert.equal(params[11], "ElderApp/1.0");
});

test("recordConsent：缺 consentType / consentVersion → invalid_payload，不打 DB", async () => {
  const pg = makeMockPg([]);
  const r1 = await recordConsent(
    { consentVersion: "1.0.0" },
    { pg },
  );
  assert.deepEqual(r1, { success: false, error: "invalid_payload" });
  const r2 = await recordConsent(
    { consentType: "privacy_terms" },
    { pg },
  );
  assert.deepEqual(r2, { success: false, error: "invalid_payload" });
  assert.equal(pg.calls.length, 0); // 未觸發 query
});

test("recordConsent：action=withdrawn 正規化並映射到 $6", async () => {
  const pg = makeMockPg([
    {
      id: "rec-w",
      consent_type: "privacy_terms",
      consent_version: "1.0.0",
      action: "withdrawn",
      agreed_at: "2026-06-08T01:00:00.000Z",
    },
  ]);
  const result = await recordConsent(
    {
      firebaseUid: "uid-x",
      consentType: "privacy_terms",
      consentVersion: "1.0.0",
      action: "withdrawn",
    },
    { pg },
  );
  assert.equal(result.success, true);
  assert.equal(result.record.action, "withdrawn");
  assert.equal(pg.calls[0].params[5], "withdrawn");
});

test("recordConsent：空字串可選欄位映射為 null（不寫空字串）", async () => {
  const pg = makeMockPg([
    {
      id: "rec-n",
      consent_type: "microphone",
      consent_version: "2",
      action: "granted",
      agreed_at: "2026-06-08T02:00:00.000Z",
    },
  ]);
  await recordConsent(
    {
      consentType: "microphone",
      consentVersion: "2",
      userId: "  ",
      source: "",
      ip: "",
      userAgent: "  ",
    },
    { pg },
  );
  const { params } = pg.calls[0];
  assert.equal(params[0], null); // userId 空白 → null
  assert.equal(params[6], null); // source 空 → null
  assert.equal(params[10], null); // ip 空 → null
  assert.equal(params[11], null); // userAgent 空白 → null
});

test("getConsent：current 取每 type 最新一筆、history 為全列表、皆遮蔽 PII", async () => {
  // rows 已依 created_at desc 排序（mock 直接回傳此順序）。
  const rows = [
    {
      id: "h4",
      consent_type: "privacy_terms",
      consent_version: "2.0.0",
      action: "withdrawn",
      agreed_at: "2026-06-08T04:00:00.000Z",
      withdrawn_at: "2026-06-08T04:00:00.000Z",
    },
    {
      id: "h3",
      consent_type: "notification",
      consent_version: "1.0.0",
      action: "granted",
      agreed_at: "2026-06-08T03:00:00.000Z",
      withdrawn_at: null,
    },
    {
      id: "h2",
      consent_type: "privacy_terms",
      consent_version: "1.0.0",
      action: "granted",
      agreed_at: "2026-06-07T00:00:00.000Z",
      withdrawn_at: null,
    },
  ];
  const pg = makeMockPg(rows);

  const result = await getConsent(
    { userId: "11111111-1111-1111-1111-111111111111" },
    { pg },
  );

  assert.equal(result.success, true);
  // history：全列表（3 筆），保留 withdrawnAt，無 PII
  assert.equal(result.history.length, 3);
  for (const h of result.history) {
    assert.ok(!("ip" in h));
    assert.ok(!("userAgent" in h));
    assert.ok("withdrawnAt" in h);
  }
  // current：每 type 最新（privacy_terms 取 2.0.0/withdrawn、notification 取 1.0.0）
  assert.equal(result.current.length, 2);
  const privacy = result.current.find((c) => c.consentType === "privacy_terms");
  assert.equal(privacy.consentVersion, "2.0.0");
  assert.equal(privacy.action, "withdrawn");
  const notif = result.current.find((c) => c.consentType === "notification");
  assert.equal(notif.consentVersion, "1.0.0");
  for (const c of result.current) {
    assert.ok(!("ip" in c));
    assert.ok(!("userAgent" in c));
  }

  // WHERE 用 user_id；SELECT 不撈 ip / user_agent
  const { text, params } = pg.calls[0];
  assert.match(text, /WHERE user_id = \$1/);
  assert.doesNotMatch(text, /ip/);
  assert.doesNotMatch(text, /user_agent/);
  assert.equal(params[0], "11111111-1111-1111-1111-111111111111");
});

test("getConsent：firebaseUid 走 users 子查詢解析", async () => {
  const pg = makeMockPg([]);
  const result = await getConsent({ firebaseUid: "uid-fb" }, { pg });
  assert.equal(result.success, true);
  assert.deepEqual(result.current, []);
  assert.deepEqual(result.history, []);
  const { text, params } = pg.calls[0];
  assert.match(text, /SELECT id FROM users WHERE firebase_uid = \$1/);
  assert.equal(params[0], "uid-fb");
});

test("getConsent：elderId 走 elder_id 過濾", async () => {
  const pg = makeMockPg([]);
  await getConsent(
    { elderId: "22222222-2222-2222-2222-222222222222" },
    { pg },
  );
  assert.match(pg.calls[0].text, /WHERE elder_id = \$1/);
});

test("getConsent：無任何識別 → invalid_payload，不打 DB", async () => {
  const pg = makeMockPg([]);
  const result = await getConsent({}, { pg });
  assert.deepEqual(result, { success: false, error: "invalid_payload" });
  assert.equal(pg.calls.length, 0);
});

test("recordConsent：DB 例外往上拋（由 route 轉 500）", async () => {
  const pg = makeMockPg([], new Error("db down"));
  await assert.rejects(
    () =>
      recordConsent(
        { consentType: "privacy_terms", consentVersion: "1.0.0" },
        { pg },
      ),
    /db down/,
  );
});
