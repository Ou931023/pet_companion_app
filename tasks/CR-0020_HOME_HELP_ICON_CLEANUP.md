<!--# CR-0020 Home Help Icon Cleanup 任務檔

## 目標

首頁右上角或上方的問號圖示目前排版過於突兀。請調整成正式產品感較好的「使用教學入口」。

## 要求

1. 不要移除教學入口。
2. 問號 icon 要縮小、降低突兀感。
3. 視覺要和首頁其他按鈕一致，例如簽到、金幣、更換外觀。
4. 可以改成淡色圓形 icon button。
5. 可以改用較柔和的 icon，例如 help_outline、lightbulb、menu_book。
6. 點擊後仍然觸發重新觀看新手導覽或使用教學。
7. 支援小螢幕，不可 overflow。
8. 不要混入其他功能。

## 禁止修改

不要修改：
- Realtime
- Agent tools
- Memory
- pet skin purchase flow
- onboarding coach mark 主流程
- auth/admin
- runtime data
- raw assets

## 檢查檔案

請檢查：
- lib/screens/home_screen.dart
- 首頁 top bar / header 相關 widget
- 導覽入口相關 callback
- home_screen layout 測試

## 測試

請執行：
- flutter analyze
- flutter test
- home_screen 相關測試

## Commit

commit message：

CR-0020 home help icon cleanup

不要 push。

## 回報

請回報：
- 問號圖示如何調整
- 點擊後是否仍可開啟導覽
- 修改檔案
- 測試結果
- commit hash>