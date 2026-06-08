# Logging and PII Redaction — AI Pet Companion（後端）

> 對應 CR-0047（Production Logging Redaction and PII De-identification）。
> 本文件說明後端 log 的去識別化原則、哪些資料不會落 log、以及如何在不暴露個資的前提下除錯。
> 紅線：log 去識別化**只改輸出內容**，不改任何 try/catch 控制流、return / throw 時機，不吞錯。

相關程式：
- `backend/stt_proxy/config/env.js` — 既有 masking primitive（`maskSecret / maskEmail / maskPhone / maskDatabaseUrl / describeMaskedConfig`），**單一遮蔽規則來源**。
- `backend/stt_proxy/services/privacy/redaction.js` — 物件 / 錯誤層遮蔽（delegate env.js primitive，不重造）。
- `backend/stt_proxy/services/privacy/redaction.test.js` — 單元測試（用假 secret）。

---

## 1. 設計原則

1. **不重造 masking**：所有單值遮蔽（token / email / phone / DATABASE_URL）一律 delegate `config/env.js`。`redaction.js` 只補「物件遞迴 / 錯誤摘要 / log payload」層。
2. **secret 兩環境恆遮**：development / staging / production 都不會印出完整 token / secret / key / DATABASE_URL / email / phone。
3. **環境差異只在自由文字截斷長度與是否附 stack**，不在「是否遮蔽 secret」。由 `config/env.js` 的 `isProduction()` 控制（NODE_ENV=test 永遠視為非 production）。
4. **不 mutate 入參**：`redactObject` 回新物件，並防循環參照與過深遞迴（深度上限 6）。
5. **不吞錯**：遮蔽只作用在「印什麼」，不改錯誤處理流程、不改回傳值、不改 throw 時機。

---

## 2. redaction.js API

| 函式 | 用途 |
|---|---|
| `redactToken(v)` | token / secret 遮蔽（delegate `maskSecret`） |
| `redactEmail(v)` | email 遮蔽（delegate `maskEmail`） |
| `redactPhone(v)` | phone 遮蔽（delegate `maskPhone`） |
| `redactDatabaseUrl(v)` | DATABASE_URL 只保留 scheme（delegate `maskDatabaseUrl`） |
| `redactObject(v)` | 遞迴遮蔽敏感 key、截斷自由文字；回新物件，不 mutate |
| `safeErrorMessage(error)` | 只回 `code` / 遮蔽過的 `message`；**不含 stack / request body / 完整 error / token** |
| `safeLogPayload(payload)` | 對 log 附帶物件套 `redactObject`（production 完整遮蔽 + 截斷） |

### 2.1 敏感 key（一律以小寫精確比對 key 名稱）

- **直接遮蔽為 `[REDACTED]`**：`token / accessToken / idToken / refreshToken / authorization / apiKey / key / secret / password / telegramToken / telegramBotToken / openaiApiKey / botToken / chatId`
- **遮蔽為對應 mask**：`email`（local 前 2 碼）、`phone`（中段遮）、`databaseUrl`（只留 scheme）
- **自由文字截斷 + 標記**：`transcript / message / conversation / memory / reason / summary / userText / aiReply / originalUserText`
  - production：一律 `[REDACTED]`（不留前綴）。
  - development / staging：僅保留前 64 字作為除錯提示，超過則加 `…[truncated]`。

### 2.2 一般長字串

非敏感 key 的長字串也會截斷（production 200 字 / dev 1000 字），避免整包 request body 落 log。

---

## 3. Production log 不會保存的資料

- 完整對話原文（user transcript / assistant reply）。
- Care Alert 的完整 `summary` / `reason`。
- email / phone 完整值。
- token / secret / API key / Telegram bot token / Telegram chat id。
- DATABASE_URL（含帳密 / db 名）。
- 錯誤 stack trace、request body 全文、headers、完整第三方 error 物件。

## 4. Production log 可以保留的資料（供維運除錯）

- error code / route / HTTP status code。
- 經遮蔽的安全 message（`safeErrorMessage`）。
- 去識別化 / 弱識別 id（如 elderId、alertId、riskLevel）與 timestamp。

---

## 5. Care Alert / Memory / Transcript logging 原則

- **Care Alert**：可記 `elderId` / `alertId` / `riskLevel` / 狀態轉換 / op 名稱與 `safeErrorMessage`；**不記** `summary` / `reason` / 對話片段全文。`careAlertStoreService.js` 的 DB 例外本就只記 `op + error.message`（已合規）。
- **Memory**：`memoryExtractor` 失敗時只記 `safeErrorMessage(err)`，**不再印 stack 全文、不再印 userText 片段**（修 Audit P2-4）。`memory/*` 的 DB fallback log 改用 `safeErrorMessage`，避免 `error?.message || error` 在 message 缺漏時落回完整 error 物件。
- **Transcript**：對話原文不寫入後端 log；如需診斷，記 turn id / 長度 / 結果旗標，不記內容。

## 6. 第三方錯誤 payload 處理原則

OpenAI / Firebase / Telegram / Tavily 等 SDK 的錯誤可能在 `error.message` 內嵌金鑰或 PII。`safeErrorMessage` 會對 message 再做一次 scrub：

- `sk-…` 風格金鑰 → mask。
- `Bearer <token>` → `Bearer [REDACTED]`。
- JWT（三段 base64url）→ `[REDACTED]`。
- email → mask。

因此即使第三方把敏感字串塞進 message，也不會原樣落 log。

---

## 7. 如何在不暴露個資的前提下除錯

1. **看 error code / route / status**：多數問題可由 `safeErrorMessage` 的 code 與 route 定位。
2. **dev/staging 開較長截斷**：非 production 環境保留 64 字自由文字前綴與一般字串 1000 字上限，足以辨識上下文。
3. **需要更詳細時走本機 development**：在本機 `NODE_ENV` 非 production 下重現，不要在 production 放寬遮蔽。
4. **絕不**為了除錯把 token / 對話原文 / summary 印進 production log；改用 turn id / 長度 / 結果旗標等去識別化線索。

---

## 8. 測試

`services/privacy/redaction.test.js`（`node --test`）涵蓋：token / email / phone / DATABASE_URL 遮蔽、nested object 遞迴遮蔽、原物件不被 mutate、循環參照、敏感 key 遮蔽、`safeErrorMessage` 不含 token / stack、Care Alert summary·reason 不完整出現、`describeMaskedConfig` 不洩 secret。測試一律使用**假 secret**（如 `sk-test-…`），不得硬編真實金鑰。

---

## 9. 後續（FU，非本案）

- FU-1：Flutter `realtime_voice_service.dart` 的 `_log` release 抑制（🔒，realtime-voice-agent，需 checkpoint）。
- FU-2：低風險 technical debugPrint 全面收斂為集中 helper（漸進）。
- FU-3：考慮在 `server.js` 全域 error handler 統一套 `safeLogPayload`。
