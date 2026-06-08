# Caregiver 帳號與授權關聯 Provisioning（CR-0043）

對應 CR-0043（補 Audit §12 #5「帳號管理」provisioning 層；接 CR-0040 scope / CR-0041 身分解析 / CR-0042 caregiver_web 登入）。

本文件說明 super_admin 如何建立 caregiver 帳號、以路線 B 綁定 `firebaseUid`、指派 / 停用授權關聯（`resident_caregiver_links`），以及 role / status 的語意與 migration 013 的對應。

實作：
- `backend/stt_proxy/services/admin/caregiverProvisioningService.js`（caregiver 帳號）
- `backend/stt_proxy/services/admin/residentLinkProvisioningService.js`（授權關聯）
- 路由：`backend/stt_proxy/server.js`（8 條，全部掛 `requireAdmin`）
- 停用閘：`backend/stt_proxy/services/admin/adminAuthContext.js`（`users.status`）
- schema：`backend/stt_proxy/db/migrations/014_add_users_status.sql`

---

## 1. 權限模型（super_admin-only）

所有 provisioning 路由皆掛 `requireAdmin`（共享 `ADMIN_API_TOKEN`，字面比對，fail-closed）：

- 無 token → **401 `missing_admin_token`**。
- 任何非共享 token（含**有效的 caregiver Firebase idToken**）→ **403 `admin_permission_required`**。
  caregiver 進不來：`requireAdmin` 只認字面 `ADMIN_API_TOKEN`，連 idToken 驗證都不走。
- 共享 token → 2xx。

**production 紅線**：`ADMIN_API_TOKEN` 是最高權限共享密鑰，**不可發給一般照護人員**。一般照護人員只應持自己的 Firebase 帳號（caregiver idToken），其可見範圍受 `resident_caregiver_links` 限制。要讓 DB-backed super_admin（`role=admin` via idToken）也能用管理路由，是後續 FU（`requireSuperAdmin`），本案未做。

稽核：每筆建立 / 修改 / 停用都寫 `auditLogService.logAudit`，`actorType='super_admin'`、`actorId=null`（共享 token 無 per-actor 身分）、`metadata` 只放結構化非敏感欄位（無 PII / email 原文 / token）。

---

## 2. Caregiver 帳號路由

| Method | Path | 說明 |
| --- | --- | --- |
| GET | `/api/admin/caregivers` | 列出所有 caregiver（`role='caregiver'`） |
| POST | `/api/admin/caregivers` | 建立 caregiver（email 必填且全域唯一；firebaseUid 可省略=pending） |
| PATCH | `/api/admin/caregivers/:id` | 改 displayName / email / firebaseUid（email 改動仍須唯一） |
| PATCH | `/api/admin/caregivers/:id/status` | 設定 `status`：`active` \| `inactive` |

對外安全欄位（**絕不回** `password_hash` / `provider_user_id` / 任何 token）：
`id` / `displayName` / `emailMasked`（遮蔽，如 `nu***@clinic.org`）/ `role` / `status` / `firebaseUid` / `createdAt` / `updatedAt`。

錯誤碼：`email_required`→400、`email_exists`→409、`invalid_status`→400、`invalid_payload`→400、`not_found`→404。

> email 唯一性目前為 **app-level SELECT 檢查**（全域，含既有 elder email），未加 DB unique index（避免衝撞既有 elder email）。super_admin-only 低併發可接受，存在極小競態窗口（FU：DB 層唯一約束）。

---

## 3. 路線 B：pending caregiver 綁定 `firebaseUid`

本案採**路線 B（super_admin 顯式綁定）**，不做 email 自動認領（拆 FU-CR-0043a）。流程：

1. super_admin `POST /api/admin/caregivers`，只給 `email`（+ 可選 `displayName`）。
   → 建立 `role='caregiver'`、`status='active'`、`firebase_uid=null` 的 **pending record**。
   **無明文密碼**——caregiver 全程走 Firebase，`users` 無 password 欄。
2. caregiver 於 App / Firebase console 取得自己的 Firebase `uid`，經機構帶給 super_admin。
3. super_admin `PATCH /api/admin/caregivers/:id`，帶 `{ "firebaseUid": "<uid>" }` 完成綁定。
4. 該 caregiver 首次以 idToken 登入即被 `adminAuthContext.findUserByFirebaseUid` 命中 → 解析為 caregiver。

---

## 4. 授權關聯（resident_caregiver_links）路由

| Method | Path | 說明 |
| --- | --- | --- |
| GET | `/api/admin/resident-caregiver-links` | 列出所有關聯（含已停用，join resident / caregiver 名稱） |
| POST | `/api/admin/resident-caregiver-links` | 建立關聯（residentId + caregiverId + role） |
| PATCH | `/api/admin/resident-caregiver-links/:id` | 改 role |
| DELETE | `/api/admin/resident-caregiver-links/:id` | 停用（soft-disable，不實刪資料） |

對外欄位：`id` / `residentId` / `residentName` / `caregiverId` / `caregiverName` / `role` / `status`（`active` \| `inactive`）/ `createdAt` / `updatedAt`。

建立前置檢查：resident（elder）與 caregiver（`role='caregiver'`）須**存在**；同一 caregiver+elder 已有 active 關聯則**不建第二筆**（`link_exists`，呼應唯一索引 `idx_rcl_unique_active`）。

錯誤碼：`invalid_payload`→400、`invalid_role`→400、`resident_not_found`→404、`caregiver_not_found`→404、`link_exists`→409、`invalid_status`→400、`not_found`→404。

---

## 5. role 語意與 migration 013 對應

授權 `role` 採 **migration 013 既有值為準**：`primary` | `secondary` | `viewer`。

| 概念 | 正規值（013） | 備註 |
| --- | --- | --- |
| 主責照護人員 | `primary` | 預設值 |
| 備援 / backup | `secondary` | 輸入 `backup` 會被正規化為 `secondary`（alias） |
| 唯讀 | `viewer` | |

---

## 6. status 語意與「停用即時失效」

有兩套 status，**詞彙刻意分開**：

| 對象 | DB 欄位 | DB 值域 | API 對外值域 |
| --- | --- | --- | --- |
| caregiver 帳號 | `users.status`（migration 014） | `active` \| `inactive` | `active` \| `inactive`（同值） |
| 授權關聯 | `resident_caregiver_links.status`（013） | `active` \| `revoked` | `active` \| `inactive`（映射） |

授權關聯 DB 維持 `active`/`revoked`（對齊 013 + `authorizationService` 查詢 + 唯一索引），provisioning service 做 `inactive ↔ revoked` 映射（停用 = `UPDATE status='revoked', revoked_at=NOW()`）。`authorizationService.js` **零改動**。

**停用即時失效（兩條路徑）**：
- 停用 **link**（DELETE 或設 inactive）→ DB `status='revoked'` → `authorizationService` 只查 `status='active'` → caregiver **立即看不到**該住民的 Care Alert / 任務。
- 停用 **caregiver**（`status='inactive'`）→ `adminAuthContext` 在身分解析、role 分派**之前**檢查 `users.status`，`inactive` → **403**，根本進不到 scope 過濾。
  - `users.status` 為 NULL / 缺值（舊 row、未跑 migration 014）→ 視為 `active`（向後相容）。
  - 共享 super_admin token 路徑不查 DB → 不受此閘影響。

---

## 7. 測試與限制（誠實標註）

- 全程 mock pg（`setPgForTest`）+ stub firebaseAdmin（`setFirebaseAdminForTest`）。
  **未對真 Postgres / 真 Firebase 金鑰驗證**；migration 014 只做靜態冪等覆核，**未對真 DB 跑**。
- 端到端 scope refresh（建 link → caregiver 看得到 → 停用 → 看不到）以 mock pg + caregiver idToken stub 驗證。
- 後端測試：
  - `services/admin/caregiverProvisioningService.test.js`
  - `services/admin/residentLinkProvisioningService.test.js`
  - `services/admin/caregiverProvisioningEndpoint.test.js`
  - `services/admin/adminAuthContext.test.js`（含停用閘）
  - `db/migration014.test.js`
- caregiver_web 管理 UI = **CR-0044**（frontend-ux，本案不含）。
- email 自動認領 = **FU-CR-0043a**（本案不含）。
