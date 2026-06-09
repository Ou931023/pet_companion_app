# VOICE_CARE_ALERT_FLOW — 語音對話的風險側錄與 Care Alert

本文件說明 Realtime 語音對話（`VoiceAgentController`）如何在陪伴過程中旁路建立 Care Alert、persist / notify 門檻，以及與打字聊天路徑的一致性。

最後更新：CR-0052。對照：`docs/TYPED_CHAT_CARE_ALERT_FLOW.md`、`docs/SAFETY_BOUNDARIES.md`。

---

## 1. 流程概觀

1. 長者語音對話 → Realtime 取得 final transcript → `VoiceAgentController` 呼叫後端 companion 分析（`CompanionEngineService.analyze`），回傳 `CompanionAnalysisResult`（含 `safety.riskLevel`、`safety.needsHumanSupport`、`careAlertSummary`）。
2. `_maybeCreateCareAlert(result, transcript, turnId)` 旁路執行（**純附加，不進 Realtime 狀態機 / SDP / DataChannel / 對話流程**）。
3. **persist gate**：以 canonical riskLevel 判定 `shouldPersistCareAlert = canonical ∈ {medium, high, urgent}`。`low`（含 legacy `normal`）直接 return，不建立、不送 `/notify`。
4. 同一輪去重：`turnId` 為空或等於 `_lastAlertedTurnId` 則略過（一輪只建一筆）。
5. 通過後：
   - 本機 `careAlertController.addAlert(alert)`（on-device 紀錄）。
   - fire-and-forget `CareAlertNotificationService.notify(sttProxyUrl, alert)` → `POST /api/care-alerts/notify`（後端 persist + 通知管線）。
6. notify 失敗（取不到 token / 401 / 403 / 網路 / timeout）只吞、記簡短 log，**不阻斷 Realtime、不回滾本機 alert**。

---

## 2. Persist gate vs Notify（CR-0052 重點）

| 概念 | 判定依據 | 語意 | 由誰決定 |
|---|---|---|---|
| `shouldPersistCareAlert` | canonical riskLevel ∈ `{medium, high, urgent}` | 是否建立 Care Alert 紀錄 | **Flutter persist gate**（CR-0052 新增） |
| `needsHumanSupport` | 後端 `safety.needsHumanSupport`（僅 high/urgent 為 true） | 是否需人為關懷的語意旗標 | 後端分類；**不再**作為 persist gate |
| Telegram 推播 | `TELEGRAM_NOTIFY_LEVELS = {high, urgent}` | 是否推播給照護人員 | **後端權威**（`telegramNotifyService.js`）；Flutter 不複製此決策 |

- **canonical 是強制**：`CareAlertRiskLevel.fromJson(safety.riskLevel).canonical` 先把 legacy `normal→low`、`attention→medium` 再比對，避免漏接 legacy 值；新 alert 也以 canonical 建構，不帶 legacy `normal/attention`（與 CR-0051 同向）。
- medium 語音會 persist 但**不**推播 Telegram（後端擋下），故不會洗版。
- Flutter 端不自行決定 Telegram：medium 仍照常送 `/notify`，由後端依授權關聯 + `shouldTelegramNotify` 處理。若 Flutter 自行擋 medium notify，medium 就不會被後端持久化，等於沒對齊。

---

## 3. 與打字聊天的一致性

| 項目 | 語音（`companion_analysis`） | 打字（`companion_chat`） |
|---|---|---|
| 分類腦 | `safety_guard` / companion 分析 | 同一個（共用） |
| 四級代碼 | `low/medium/high/urgent` | 同 |
| persist 門檻 | `{medium, high, urgent}`（CR-0052 對齊） | `{medium, high, urgent}` |
| Telegram 門檻 | `{high, urgent}`（後端） | 同 |
| alert `source` | `companion_analysis` | `companion_chat` |
| cooldown 來源 | 獨立（key = `source::riskLevel`） | 獨立 |
| auth | Bearer 住民 idToken（CR-0045，後端權威推導 elderId） | 同 |

---

## 4. 為何長者端不顯示監控感文案

Care Alert 的定位是「陪伴過程中的異常提醒」，前台寵物以陪伴語氣互動、**後台才做風險分析與通知**（CLAUDE.md §7）。語音端 `care_alert_screen.dart`（route `careAlerts`）以「今日關心紀錄」柔和框架呈現，**不顯示 raw riskLevel / label / JSON / 「已通知照護人員」**。medium 只是多一筆同類柔和紀錄，不暴露分級、不產生被監視感。

---

## 5. 不變式（CR-0052 限制）

1. 不動 `realtime_voice_service.dart` 與 Realtime WebRTC 主流程（SDP / ICE / DataChannel）。
2. 不破壞 CR-0045 `/notify` caller auth（語音 notify 仍帶 Bearer idToken、不送 client elderId、不用 fake token）。
3. 不破壞 CR-0051 打字聊天 risk integration。
4. medium 不當 high/urgent 推播；low 不大量建立 alert。
5. 新 alert 不使用 legacy `attention`。
6. `source` 維持 `companion_analysis`（後端 cooldown 分組依據）。
7. fire-and-forget 不變；notify 失敗不阻斷對話。
