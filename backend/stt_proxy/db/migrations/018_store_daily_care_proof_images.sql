-- CR-0104：正式環境不可把照護任務照片留在 Render 暫存磁碟。
-- 照片本體與 MIME type 存入 PostgreSQL；既有 proof_image_path 暫留供舊資料相容，
-- 新寫入流程不再依賴該路徑。冪等 migration，可安全重跑。

ALTER TABLE daily_care_task_submissions
  ADD COLUMN IF NOT EXISTS proof_image_bytes BYTEA;

ALTER TABLE daily_care_task_submissions
  ADD COLUMN IF NOT EXISTS proof_mime_type TEXT;
