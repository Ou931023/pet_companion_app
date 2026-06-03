-- CR-0029：管理者端使用者帳戶管理。
-- 為 users 補上 last_login_at（「最近登入時間」），供 Admin Users API 顯示。
-- 沿用 006 的 IF NOT EXISTS 冪等慣例；不更動既有欄位、不影響登入註冊主流程。

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- Admin Users API 以 created_at DESC 排序取最近 100 筆，建索引加速。
CREATE INDEX IF NOT EXISTS idx_users_created_at
ON users (created_at DESC);
