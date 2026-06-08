# CR-0048 — Production Mock Service Build-Flavor Isolation

## 1. 任務定位

本任務接續 CR-0047。

目前已完成：

- 授權鏈 CR-0039 至 CR-0045
- Store readiness 第一輪 CR-0046
- Production logging redaction CR-0047

目前殘留正式版風險：

> Flutter App 仍可能在 `lib/app.dart` 或 provider wiring 中永久注入 mock service。  
> 即使 production config 已停用 mock，正式 build 仍不應保留會被誤用的 mock 注入路徑。

本 CR 目標是把 mock / demo / dev-only service 完整隔離到 development / test，不讓 production build 走到 mock service。

---

## 2. 本次目標

完成 Flutter production build-flavor mock isolation。

完成後應達成：

1. production build 不注入 mock service。
2. production build 不顯示 demo login / dev panel。
3. mock service 僅能在 development / test 使用。
4. 若 production 嘗試啟用 mock，應 fail-fast 或被強制關閉。
5. 不破壞 Realtime、Memory、Care Alert、Auth、Notify。
6. 測試明確覆蓋 production/dev/test 三種模式。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `lib/app.dart`
- `lib/config/app_config.dart`
- `lib/main.dart`
- `lib/**/mock*.dart`
- `test/config/*`
- 目前所有與 mock / demo / dev panel / fake service 有關的測試

---

## 4. 先盤點

修改前請盤點：

1. Flutter 目前所有 mock service。
2. Flutter 目前所有 fake / demo provider。
3. `lib/app.dart` 目前注入哪些 service。
4. AppConfig 如何判斷 production / development / test。
5. `SHOW_DEV_PANELS`、`SHOW_DEMO_LOGIN`、`ALLOW_MOCK_SERVICES` 等 flag 是否仍生效。
6. production build 是否可能經由 dart-define 開啟 mock。
7. 測試目前是否依賴 production mock 行為。
8. UI 是否仍有 Demo / Mock / Test 字樣。

---

## 5. Flutter 實作需求

### 5.1 AppConfig 強化

確認或補強：

- production 強制 `allowMockServices == false`
- production 強制 `showDevPanels == false`
- production 強制 `showDemoLogin == false`
- production 強制不允許 fake backend / fake user
- development / test 可明確允許 mock，但需透過 flag

若目前已做一部分，請補齊測試與文件。

---

### 5.2 Service Wiring

請檢查 `lib/app.dart` 與 provider wiring。

要求：

1. production path 注入正式 service。
2. development/test path 才可注入 mock service。
3. 不得在 production provider tree 中無條件建立 mock service。
4. 不得用 mock service 包裝正式 service。
5. 不得用 fake fallback 取代正式錯誤處理。
6. 若正式 service 缺必要 config，production 應顯示安全錯誤或 fail-fast，不可自動 fallback mock。

---

### 5.3 Demo / Dev UI

確認正式 build 不顯示：

- demo login
- dev panel
- mock STT
- fake mode
- debug page
- engineering-only route

若 development 仍需保留，請放在明確 guard 後。

---

## 6. 測試需求

請至少新增或更新 Flutter 測試：

1. production AppConfig 即使 dart-define 嘗試開啟 mock，也會強制關閉。
2. production provider wiring 不注入 mock service。
3. development 可在明確 flag 下使用 mock service。
4. test mode 可使用 mock service。
5. production 不顯示 demo login。
6. production 不顯示 dev panel。
7. production 不顯示 mock STT 字樣。
8. production Realtime / Care Alert / Auth provider 仍可建立正式 service。
9. 缺 production API base URL 不會 fallback mock。
10. 既有 Flutter tests 全綠或相關測試全綠。

---

## 7. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/STORE_RELEASE_CHECKLIST.md`

如需要，新增：

- `docs/FLUTTER_BUILD_FLAVORS.md`

文件需說明：

1. development / staging / production 如何切換。
2. 哪些 mock 只允許 development / test。
3. production dart-define 範例。
4. release build 前如何確認 mock 已關閉。
5. 不可在正式 build 使用 demo login / mock service。

---

## 8. 限制

本 CR 不得：

1. 修改 Realtime WebRTC 主流程。
2. 修改 Memory API 契約。
3. 修改 Care Alert notify auth。
4. 修改後端授權鏈。
5. 為了通過測試把正式 service 改成 mock。
6. 讓 production fallback 到 mock。
7. 移除 development/test 必要測試替身。
8. 大量重寫 unrelated UI。
9. 使用 hardcoded production token。
10. 偽造 release build 已通過。

---

## 9. 驗收標準

完成後必須符合：

1. production AppConfig 強制關閉 mock / demo / dev panel。
2. production provider tree 不注入 mock service。
3. development/test mock 路徑仍可測試使用。
4. production 不顯示 demo/mock/dev 字樣。
5. Flutter analyze 通過。
6. Flutter 相關測試通過。
7. CHANGE_REVIEW 已更新。
8. STORE_RELEASE_CHECKLIST 更新 mock isolation 狀態。
9. 無 hardcoded auth / fake token / sensitive log。

---

## 10. 完成回報格式

請用以下格式回報：

```md
## CR-0048 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. Mock / demo 盤點結果
-

### 4. AppConfig 改動
-

### 5. Provider wiring 改動
-

### 6. Demo / dev UI 隔離結果
-

### 7. 測試結果
-

### 8. 正式版風險檢查
- production 是否仍可能注入 mock：
- production 是否仍顯示 demo login：
- production 是否仍顯示 dev panel：
- production 是否仍 fallback mock：
- development/test mock 是否仍可測：
- 是否破壞 Realtime / Care Alert / Auth：

### 9. 殘留風險
-

### 10. 下一個建議 CR
-
```
