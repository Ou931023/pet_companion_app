# CR-0074 Demo Script and Presentation Lock

## 背景

目前 production 主要功能已完成並驗證：

* Backend Render Live：`https://ai-companion-app-7mb8.onrender.com`
* caregiver_web Live：`https://ai-companion-caregiver-web.onrender.com`
* Supabase migrations 001–016 completed
* caregiver_web 可登入與操作
* Marketplace PostgreSQL production enabled
* Daily Care Tasks PostgreSQL production enabled
* Long-term memory recall 正常
* Realtime / Auth / Care Alert / Telegram / 管理端皆進入正式 smoke 階段

本 CR 不新增功能、不改核心程式、不改後端契約。目標是把正式展示流程鎖定，產出可照著操作的 Demo Script 與備援方案。

## 目標

建立一份正式展示用文件，包含：

1. 5–7 分鐘 Demo 操作流程
2. 每一步畫面要展示什麼
3. 每一步講者要說什麼
4. 操作者要點哪裡、輸入什麼測試句
5. Care Alert / Telegram / 管理者端刷新流程
6. Marketplace / Daily Care Tasks 展示流程
7. 失敗時的測試語句觸發 Care Alert
5. 打開 Telegram，展示即時通知
6. 打開 caregiver_web，展示照護提醒
7. 展示照護商城商品列表 / 商品詳情 / 下單流程
8. 展示今日任務 / 拍照完成 / 管理端查看
9. 最後回到系統特色總結

### 3. 測試句設計

請提供展示用測試句，需避免過度危險或不適合公開展示的語句，但要足以觸發情緒 / 風險流程。

至少包含：

* 長期記憶測試句
* 打字聊天測試句
* medium care alert 測試句
* hi 5. 展示前檢查清單

包含：

* 後端 `/health`
* caregiver_web 可登入
* Telegram bot 可收訊
* iPhone App 已用 production flags 安裝
* 麥克風 / 相機權限
* 網路穩定
* 管理者 token 不外露
* 不展示 OpenAI key / Firebase key / DATABASE_URL
* 不展示真實個資

### 6. 更新 E2E 報告

若合適，請在：

```txt
docs/E2E_SMOKE_TEST_REPORT.md
```

補一小節：

```txt
Demo readiness checklist
```

只記錄展示前檢查項目，不要假裝人工 smoke 全部已 PASS。

### 7. 測試與檢查

此 CR 原則上 docs-only。請執行：

```bash
git status --short
```

確認沒有 secret 檔案被加入。

若只改 docs/tasks，不需要跑完整 backend/flutter test；但要明確回報 docs-only。

### 8. Commit

```bash
git add docs tasks
git commit -m "Add demo script and presentation readiness checklist"
```

不得加入：

* `.en期記憶與照護管理

