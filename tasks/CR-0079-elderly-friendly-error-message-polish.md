# CR-0079 Elderly Friendly Error Message Polish

## 背景

CR-0076 Formal Companion Retention UX Audit 已完成，結論指出目前 App 已具備正式長者陪伴 App 的基本價值鏈，但仍存在一個 Demo 前必修的程式碼 P0：

App 有 3 處會將工程錯誤訊息直接顯示給長者，降低正式感，也可能讓長者不知所措。

已知問題位置：

1. `agent_router_service.dart:66`

   * `error.toString()` 直接外顯

2. `realtime_voice_service.dart:794/798`

   * 顯示「Realtime API 發生錯誤」
   * 可能顯示英文 API 錯誤訊息

3. `settings_screen.dart:890`

   * 顯示 enum 名稱

本 CR 目標是將上述錯誤訊息改成白話、長者友善、可行動的提示，不改變功能流程、不改 API 契約。

## 重要限制

`realtime_voice_service.dart` 是 🔒 檔案。

在修改前，請先進行 architecture-agent review / approval，確認最小修改範圍。

本 CR 只允許修正錯誤訊息顯示，不得重構 Realtime 主流程。

## 目sponse
* mock fallback

## 修改範圍

只允許檢查與最小修改以下相關檔案：

```text
lib/services/agent_router_service.dart
lib/services/realtime_voice_service.dart
lib/screens/settings_screen.dart
```

若實際檔案路徑不同，請先 grep 確認。

可視需要新增一個小型 helper，例如：

```text
lib/utils/user_friendly_error_message.dart
```

但只有在能減少重複且不擴大風險時才新增。

## 必修問題 1：agent_router_service.dart

### 現況問題

`error.toString()` 可能將工程細節直接顯示給使用者。

# log
* UI / response 只能得到 friendly message

## 必修問題 2：realtime_voice_service.dart

### 現況問題

使用者可能看到：

```text
Realtime API 發生錯誤
```

或英文 API 錯誤訊息。

這對長者不友善，也會讓 Demo 看起來像工程測試版。

### 目標

語音錯誤要轉成白話提示，且引導改用可行替代方式。

### 建議文案

語音連線失敗：

```text
語音連線暫時不穩，請稍後再試一次，也可以先用打字和寵物聊天。
```

麥克風或權限問題：

```text
目前無法使用麥克風，請確認手機已允許麥克風權限。
```

服務忙碌或 API 錯誤：

```text
寵物現在回應比較慢，請稍等一下再試一次。
```

### 要求

* 不可顯示 `Realtime API`
* 不可顯示英文 API response
* 不可顯示 exception 類名
* 不可顯示 backend/internal route
* 不可改變 Realtime 連線主流程
* 不可加入 demo fallback
* 連線暫時不穩，請稍後再試一次，也可以先用打字和寵物聊天。
error.toString() → 目前這個功能暫時無法使用，請稍後再試一次。
enum raw name → 對應中文狀態文字。
unknown → 目前狀態暫時無法確認，請稍後再試。
network error → 目前連線不太穩，請確認網路後再試一次。
timeout → 等待時間比較久，請稍後再試一次。
```

## 文件更新

請新增或更新：

```text
docs/ERROR_MESSAGE_POLISH_CR0079.md
```

內容包含：

1. 修改摘要
2. 原始問題
3. 修改檔案
4. 白話文案對照表
5. 未改動範()`。
3. 設定頁不應看到 enum raw value。
4. 使用者看到的訊息應該知道下一步可以怎麼做。

## Commit

```bash
git add lib docs tasks
git commit -m "Polish elderly friendly error messages"
```

不得加入：

* `.env`
* Firebase private key
* `google-services.json`
* `GoogleService-Info.plist`
* keystore
* `key.properties`
* Render env
* API key
* `ADMIN_API_TOKEN`

## 驗收標準

完成後應能回答：

1. 哪 3 處工程訊息被修掉？
2. 長者現在會看到什麼白話訊息？
3. Realtime 失敗時是否會引導改用打字？
4. settings enum 是否已轉成中文文案？
5. 是否沒有改動 Realtime 主流程？
6. `flutter analyze` 是否通過？

