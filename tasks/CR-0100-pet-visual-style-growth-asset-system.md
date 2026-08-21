# CR-0100 Pet Visual Style / Growth / Asset System

## 目標

讓寵物素材系統支援正式產品化需求：

- Q 版 / 真實版偏好選擇。
- 從幼年到成年等成長階段。
- 更多低成本但有陪伴感的互動動畫。
- App 與 caregiver analytics 能看到真實使用偏好資料。

本 CR 不要求一次產完所有寵物素材。策略文件見：

- `docs/PET_VISUAL_ASSET_STRATEGY_CR0100.md`

## 已完成基礎

- `PetVisualProfile` 已建立。
- 目前素材誠實標示為 `cute / adult`。
- `pet_interaction` 與 `pet_style_changed` 事件已可帶 `petType / visualStyle / growthStage`。
- caregiver analytics 已可顯示寵物類型、視覺風格、成長階段。

## CR-0100A：主寵物 Q/real 素材候選

### 範圍

先做 `dog`，不一次鋪所有寵物。

候選圖：

- Q 版 dog：normal / happy / caring / sad。
- 真實版 dog：normal / happy / caring / sad。

### 驗收

- 1024 x 1024 PNG。
- 透明背景。
- 無浮水印、文字、邊框。
- 同一風格角色一致。
- 長者一眼看得懂表情。
- 不接 App 程式、不改 `AssetPaths`。

## CR-0100B：v2 AssetPaths resolver

### 範圍

新增 v2 path resolver，支援：

```text
assets/pets/v2/<visualStyle>/<growthStage>/<pet>/...
```

保留現有 v1 fallback，不搬動舊素材。

### 驗收

- v1 既有測試不破。
- v2 path 對缺素材時 fallback 到 v1。
- `PetVisualProfile` 能描述 v2 素材能力。

## CR-0100C：App 內 Q/real 偏好 UI

### 範圍

在更換外觀 sheet 加入風格選擇：

- Q版
- 真實版

尚未有真實版素材的 pet 不顯示或 disabled，不可假裝可用。

### Tracking

成功切換後上報：

- `eventType: pet_style_changed`
- `petType`
- `selectedPetType`
- `visualStyle`
- `growthStage`
- `source`

### 驗收

- 長者端文案白話。
- 大字模式不 overflow。
- caregiver analytics 看得到切換後偏好。

## CR-0100D：互動動畫 overlay

### 範圍

先做三個互動：

- `pat`：摸摸。
- `feed`：餵食。
- `celebrate`：完成任務 / 簽到 / 拼圖。

本階段可用 Flutter overlay / 簡單 particle，不必先新增大量角色本體 frame。

### 驗收

- 點寵物或餵食時有可見回饋。
- 完成任務有開心回饋。
- 不影響 Realtime voice state。

## CR-0100E：成長階段

### 範圍

先只做 `dog`：

- baby
- adult

暫不做 young，避免素材量過大。

### 驗收

- 有本機與後端可追蹤的 growth stage。
- App 端可顯示目前階段。
- caregiver analytics 可顯示目前成長階段。
- 不宣稱醫療或療效。

## 不做事項

- 不在 runtime 即時 AI 生圖。
- 不一次改 3D / Rive 為寵物本體。
- 不重寫 Realtime WebRTC。
- 不新增 demo-only fallback。
- 不把未完成真實版素材顯示在正式 UI。

## 測試建議

- `flutter test test/models/pet_skin_test.dart`
- `flutter test test/widgets/pet_avatar_test.dart`
- `flutter test test/widgets/pet_skin_picker_test.dart`
- `flutter test test/home_screen_layout_test.dart`
- `node --test backend/stt_proxy/services/appUsageEventStore.test.js`
- `node --test backend/stt_proxy/services/admin/caregiverAnalyticsService.test.js`
- `node --test caregiver_web/analytics_dashboard.test.js`
