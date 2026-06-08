-- CR-0043 B1：users.status（caregiver 啟用/停用生命週期）。
-- 契約見 docs/CHANGE_REVIEW.md CR-0043 §3 裁決 1 與 docs/CAREGIVER_PROVISIONING.md。
--
-- 裁決（§3 #1）：caregiver 的「啟用/停用」狀態用獨立欄 `users.status`（值域 active|inactive），
-- 不復用 `binding_status`（其語意=長者端 Firebase 綁定 pending/verified，復用會污染語意並影響
-- 長者登入流程）。新欄預設 'active' → 對既有 row（含長者/caregiver）零破壞、向後相容。
-- adminAuthContext 的 inactive 閘把「NULL/缺值」視為 active（見 CR-0043 §3 #4）。
--
-- migrate.js 啟動時 glob migrations/*.sql 依檔名排序重跑、無 schema_migrations 追蹤，
-- 故本檔必須完全冪等：ADD COLUMN IF NOT EXISTS，重複執行不報錯、不副作用。
-- 比照 006/013 的冪等補欄位寫法。本批 migration only：只加欄，不接 service / 路由。

-- users.status：caregiver 帳號啟用狀態（active|inactive）。預設 active 確保既有 row 不受影響。
ALTER TABLE users ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
