// 知情同意稽核 store（CR-0036 Batch 2）。
//
// 對應 DB migration db/migrations/010_create_consent_records.sql（append-only 稽核表）
// 與 PROJECT_ARCHITECTURE.md §10.4 契約。
//
// 設計選擇：**DB-only**。
//   consent_records 是稽核資料（知情同意軌跡），不可用 JSON fallback 假裝成功
//   （見 pet_companion_app/CLAUDE.md §3、§9）。連不到 DB 時讓底層 query 拋例外，
//   由 server.js route 轉成明確的 500 consent_failed，而不是靜默寫進 JSON 假成功。
//   （對照 careAlertStoreService 的 JSON store：那是可降級的營運資料；稽核資料不同。）
//
// PII 紅線（§10.4 / migration 010 註解）：
//   ip / user_agent 只在 recordConsent 寫入 DB 供稽核；
//   recordConsent 回傳的 record 與 getConsent 回傳的 current/history **絕不含** ip / user_agent。
//
// 測試：以 options.pg（或 setPgForTest）注入 mock pool，達到「不需真 DB」即可單測。

const defaultPg = require("../db/postgres");

// 預設用真實 Postgres；測試可用 setPgForTest 注入 mock pool。
let activePg = defaultPg;

// 測試專用：注入 / 還原 pg（mock pool 需提供 query(text, params) → { rows }）。
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// granted / withdrawn，預設 granted；未知值正規化為 granted。
function normalizeAction(value) {
  const raw = (value == null ? "" : String(value)).trim().toLowerCase();
  return raw === "withdrawn" ? "withdrawn" : "granted";
}

// timestamptz 從 pg 取回是 JS Date；契約要求 ISO8601 字串。
function toIso(value) {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  return value;
}

function strOrNull(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

// 把 RETURNING row 映射為對外 record（遮蔽 PII：不含 ip / user_agent）。
function toRecord(row) {
  return {
    id: row.id,
    consentType: row.consent_type,
    consentVersion: row.consent_version,
    action: row.action,
    agreedAt: toIso(row.agreed_at),
  };
}

// 記錄一次同意 / 撤回（寫一列，append-only）。
// input: { userId, elderId, firebaseUid, consentType, consentVersion,
//          action, source, appVersion, platform, agreedAt, ip, userAgent }
// 回 { success:true, record:{ id, consentType, consentVersion, action, agreedAt } }
// 缺必填 → { success:false, error:"invalid_payload" }。DB 例外往上拋（route 轉 500）。
async function recordConsent(input = {}, options = {}) {
  const pg = options.pg || activePg;

  const consentType = strOrNull(input.consentType);
  const consentVersion = strOrNull(input.consentVersion);
  if (!consentType || !consentVersion) {
    return { success: false, error: "invalid_payload" };
  }

  const action = normalizeAction(input.action);
  const userId = strOrNull(input.userId);
  const elderId = strOrNull(input.elderId);
  const firebaseUid = strOrNull(input.firebaseUid);

  // user_id / elder_id：直接帶優先；否則用 firebaseUid 解析既有 users；都無 → null
  // （兩欄 nullable，保留稽核軌跡）。withdrawn 時補 withdrawn_at（不刪舊列）。
  const result = await pg.query(
    `INSERT INTO consent_records (
       user_id, elder_id, consent_type, consent_version, action, source,
       agreed_at, withdrawn_at, app_version, platform, ip, user_agent
     ) VALUES (
       COALESCE($1::uuid, (SELECT id FROM users WHERE firebase_uid = $3 LIMIT 1)),
       COALESCE($2::uuid, (SELECT elder_id FROM users WHERE firebase_uid = $3 LIMIT 1)),
       $4, $5, $6, $7,
       COALESCE($8::timestamptz, NOW()),
       CASE WHEN $6 = 'withdrawn' THEN COALESCE($8::timestamptz, NOW()) ELSE NULL END,
       $9, $10, $11, $12
     )
     RETURNING id, consent_type, consent_version, action, agreed_at`,
    [
      userId, // $1
      elderId, // $2
      firebaseUid, // $3
      consentType, // $4
      consentVersion, // $5
      action, // $6
      strOrNull(input.source), // $7
      strOrNull(input.agreedAt), // $8
      strOrNull(input.appVersion), // $9
      strOrNull(input.platform), // $10
      strOrNull(input.ip), // $11  PII：只落 DB
      strOrNull(input.userAgent), // $12 PII：只落 DB
    ],
  );

  const row = result.rows[0];
  return { success: true, record: toRecord(row) };
}

// 查詢某使用者目前同意狀態 + 稽核歷史。
// identity: { userId } 優先，否則 { elderId }，否則 { firebaseUid }。
// 回 { success:true, current:[每個 consent_type 最新一筆], history:[全列表] }
// 缺可辨識識別 → { success:false, error:"invalid_payload" }。
// **遮蔽 PII**：current / history 都不含 ip / user_agent（SELECT 不撈該兩欄）。
async function getConsent(identity = {}, options = {}) {
  const pg = options.pg || activePg;

  const userId = strOrNull(identity.userId);
  const elderId = strOrNull(identity.elderId);
  const firebaseUid = strOrNull(identity.firebaseUid);

  let whereClause;
  let params;
  if (userId) {
    whereClause = "user_id = $1::uuid";
    params = [userId];
  } else if (elderId) {
    whereClause = "elder_id = $1::uuid";
    params = [elderId];
  } else if (firebaseUid) {
    whereClause =
      "user_id = (SELECT id FROM users WHERE firebase_uid = $1 LIMIT 1)";
    params = [firebaseUid];
  } else {
    return { success: false, error: "invalid_payload" };
  }

  // 依 created_at desc 取列；同 type 第一筆即「目前狀態」。不撈 ip / user_agent。
  const result = await pg.query(
    `SELECT id, consent_type, consent_version, action, agreed_at, withdrawn_at
     FROM consent_records
     WHERE ${whereClause}
     ORDER BY created_at DESC, agreed_at DESC`,
    params,
  );

  const rows = result.rows || [];
  const history = rows.map((row) => ({
    id: row.id,
    consentType: row.consent_type,
    consentVersion: row.consent_version,
    action: row.action,
    agreedAt: toIso(row.agreed_at),
    withdrawnAt: toIso(row.withdrawn_at),
  }));

  // current：每個 consent_type 取最新一筆（rows 已 desc，首見即最新）。
  const seen = new Set();
  const current = [];
  for (const row of rows) {
    if (seen.has(row.consent_type)) continue;
    seen.add(row.consent_type);
    current.push({
      consentType: row.consent_type,
      consentVersion: row.consent_version,
      action: row.action,
      agreedAt: toIso(row.agreed_at),
    });
  }

  return { success: true, current, history };
}

module.exports = {
  recordConsent,
  getConsent,
  // 測試 / 工具用
  setPgForTest,
  normalizeAction,
};
