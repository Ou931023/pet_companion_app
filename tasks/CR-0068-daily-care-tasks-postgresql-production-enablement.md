# CR-0068 Daily Care Tasks PostgreSQL Production Enablement

## 背景

Marketplace 已完成 JSON → PostgreSQL production enablement，migration 015 已部署，正式環境商品 API 已可用。

目前剩下 daily-care-tasks 與 marketplace 類似，production 下因 JSON fallback / runtime_data 不可作正式資料來源而被關閉或不穩定，App 端今日任務可能出現「伺服器忙線中」或無法正式使用。

## 目標

將 Daily Care Tasks 從 JSON/runtime_data 路徑正式平移到 PostgreSQL，使 production 下可用：

- 長者端今日任務列表
- 任務狀態
- 拍照完成 / 圖片上傳
- AI Vision 驗證結果
- caregiver_web 查看任務 / submission 狀態

## 必做事項

1. 盤點現有 daily-care-tasks 後端 store / routes / Flutter API service / caregiver_web 使用端點。
2. 設計 PostgreSQL schema 與 migration 016，需支援：
   - daily care task
   - task submission
   - resident / elder 關聯
   - status
   - photo metadata
   - AI verification resulb caregiver_web test docs tasks
   git commit -m "Enable daily care tasks with PostgreSQL in production"

## 驗收標準

部署後：

1. Render Shell 執行 npm run db:migrate，確認 migration 016 applied。
2. App 端今日任務不再顯示「伺服器忙線中」。
3. 長者端能看到任ck。
