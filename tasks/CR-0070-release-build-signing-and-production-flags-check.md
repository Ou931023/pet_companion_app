# CR-0070 Release Build Signing and Production Flags Check

## 背景

CR-0069 已完成 Production E2E Smoke Run #2 文件整理與 API 層 smoke：
- Backend: https://ai-companion-app-7mb8.onrender.com
- Caregiver Web: https://ai-companion-caregiver-web.onrender.com
- Marketplace production-enabled
- Daily Care Tasks production-enabled
- A1–A7 API smoke PASS
- 真機 S1–S9 / M1–M4 / D1–D5 仍需人工執行

本 CR 不新增功能，不改 Realtime / Auth / Marketplace / Daily Care Tasks 邏輯。目標是檢查 release build、簽章、production flags、store readiness，避免正式展示或上架前因 build 設定出錯。

## 目標

確認 iOS / Android release build 所需設定完整，且 production build 不會使用 localhost、舊 Render URL、dev panel、mock service 或 demo-only fallback。

## 必做事項

### 1. 檢查 Flutter production build 指令

確認文件中有正式 build 指令：

```bash
flutter run --release \
  --dart-define=APP_ENV=production \
  --dart-define=AP
