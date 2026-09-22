# 機構通知與設備整合 Runbook

更新日期：2026-09-22。Owner：architecture-agent。

依據：[CR-0109 最新裁決](CHANGE_REVIEW.md)、[架構 §4.4](../PROJECT_ARCHITECTURE.md)。本文件不是 production 啟用授權；若與早期較寬提案衝突，以 CR-0109 最新縮限為準。

## 1. 本批狀態與紅線

| 項目 | 本批允許 | 尚未允許 |
| --- | --- | --- |
| 語言切換 | owner 實作明確命令、手動 / 語音同步及限定回歸測試 | SDK / 模型 / WebRTC 傳輸 / VAD 改動 |
| LINE | 隔離、預設停用的 adapter / dispatcher / resolver interface 與注入式單測 | 接 processCareAlert、server 啟動、live voice 或真實發送 |
| Telegram | 保留現行程式與介面，記錄後續整合門檻 | 本批修改 sender / cooldown / log，或宣稱既有路徑已具完整 consent gate |
| MQTT / IR | 契約與待確認事項文件 | adapter / device policy 程式、broker client、連線、publish、設備操作 |

後端已確認缺可信機構收件映射與住民 consent gate。LINE 完成單測不代表已接線或可啟用；Telegram 既有功能不代表已通過本文件的機構授權驗收。MQTT 沒有硬體或 broker，不能宣稱可用。小黑豆只是候選 IR blaster 稱呼，未核實品牌、型號與協定。

## 2. 硬體選購前必填資料

先由機構 / 供應商提供不含秘密的產品規格、官方文件與相容性證據，再評估購買；本文件不推薦任何未查證型號。

| 確認項目 | 必須取得的資訊 / 證據 |
| --- | --- |
| 產品身分 | 製造商、完整品牌 / 型號、硬體版本、韌體版本與官方產品 / 開發文件；不能僅憑「小黑豆」俗稱 |
| 受控設備 | 每台燈具 / 冷氣的品牌、型號、原遙控器型號、安裝位置與所屬機構；確認是否真的支援 IR |
| 控制協定 | 原生 MQTT、官方 local API、雲端 API 或需 bridge；各方式的支援版本、文件、授權條件與停服風險。Wi-Fi / App 可控不等於支援 MQTT |
| IR 相容性 | 廠商對目標設備的明確支援或受控實測；是否需學習碼、是否只能 toggle、能否送絕對開關 / 冷氣完整設定；不憑外觀推定 |
| 狀態回報 | 實際設備回讀、獨立感測器、遙控器 / blaster 快取，或完全無回讀；回報來源、時間戳、過期判定、外部遙控器操作後能否同步 |
| 網路與安全 | 本地離線能力、網路隔離、認證、加密與憑證驗證、韌體更新、撤銷 / 重設、broker topic ACL 能力；不要求提供任何密碼或憑證 |
| 故障行為 | 斷網 / 停電 / 重啟 / 重連是否重送舊命令、是否保留指令、IR 遮擋與重複發送處理、人工接管方式 |
| 安裝與維運 | IR 視線 / 距離與干擾實測、機構同意安裝、操作權責、維修 / 支援與退換貨條件；涉及電路由合適人員處理 |

**證據分級不可混淆：** broker 接受 publish、blaster 接受命令、IR 發射完成、設備實際狀態是四件不同的事。無可信回讀只能顯示「已送出指令，設備狀態尚未確認」，不得說「冷氣已開」。只有 toggle 且無可信狀態時，不核准自動控制。

採購前 checkpoint：backend owner 提出可行協定；機構確認目標設備與操作界限；architecture-agent 審查身分 / 設備綁定、狀態證據及失敗行為。規格不足時維持待確認，不以購買後再猜測協定代替審查。

## 3. 兩通知平台的正式啟用前置

以下是未來整合的必要條件，並非本批已實作：

1. **住民獨立 opt-in**：清楚告知通知用途、機構、平台、收件者範圍、內容、high / urgent 自動觸發與撤回方式；保存可稽核的同意版本、時間、範圍及撤回狀態。一般 privacy_terms、麥克風 / OS 通知許可不能代替對外分享同意。代理同意機制若需要，須另定授權與驗證契約，不能由開發者自行假定。
2. **可信住民到機構映射**：以 server 已驗證身分及權威資料解析 elder / facility，不採信 client、LLM 或工具參數的身分欄位。
3. **可信收件綁定**：具管理權限的人完成平台目的地核對，綁定 facility、授權照護者、平台與 recipient reference；保留驗證 / 撤銷紀錄。群組須確認成員皆屬允許知悉範圍，成員或照護指派變更需重新評估 / 撤銷，不能把加入 bot 群組視為住民授權。
4. **逐次授權**：每次送出及任何重試重新檢查有效同意、active caregiver assignment、綁定與政策版本；查詢失敗、撤回、未綁定或 scope 不符一律不送。urgent 不自動豁免同意。手動 notify_caregiver 還須當次確認內容與對象。
5. **機構通道選擇**：允許不送、Telegram、LINE 或兩者；選平台不等於同意。單通道失敗不得默默改送未授權平台。既有全域 Telegram 收件設定不能直接映射所有住民。
6. **最小化內容**：僅風險四級、時間、受控照護代稱 / alert reference 與固定關心提示。不得傳逐字稿、自由文字摘要、姓名、電話、住址、日記、記憶或任意 URL。詳細資料留在有授權檢查的照護介面。
7. **結果與稽核**：每通道獨立 accepted / failed / unknown / skipped 結果；accepted 不等於送達、已讀或照護者已處理。去重至少隔離機構、住民、事件、收件綁定、通道；不以全域 source+riskLevel 抑制其他住民。不宣稱 in-process 去重能跨重啟 exactly-once。

可信 policy / consent / recipient resolver 的資料來源、DB / API、撤回及管理權限尚待精確提案與核准。單測注入的授權結果不能作 production resolver；環境開關或本機偏好也不能充當 consent gate。通知被拒不刪除既有 Care Alert；照護作業需保留非平台推播的既定人工處理流程，不把 bot 當緊急救援保障。

## 4. Setup 清單：只列變數名稱

不得讀取、提交或要求貼出 `.env`、API key、token、密碼、private key、收件目的地實值或 runtime data。由授權維運人員在受控部署設定管理實值，不放 Flutter、版本庫、聊天、截圖、測試 fixture 或 log。本 runbook 不提供設定值或帶值的命令。

| 變數名稱 | 現況 / 用途 |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | 既有 Telegram sender 的後端設定名稱；不代表取得住民授權 |
| `TELEGRAM_CARE_CHAT_ID` | 既有全域目的地設定名稱；不能代替可信機構 / 住民收件綁定 |
| `LINE_NOTIFICATIONS_ENABLED` | CR-0109 預留的啟用開關名稱；本批保持預設停用，開關不構成接線或啟用許可 |
| `LINE_CHANNEL_ACCESS_TOKEN` | LINE adapter 的後端設定名稱；本批單測不使用真實憑證 |

LINE 使用 Messaging API，不使用 LINE Notify；採既有 fetch，不增加 SDK。平台 API 與重試語義依[官方 API 文件](https://developers.line.biz/en/reference/messaging-api/#send-push-message)及[重試說明](https://developers.line.biz/en/docs/messaging-api/retrying-api-request/)核對；LINE Notify 已終止，見[官方公告](https://developers.line.biz/en/news/2025/04/01/line-notify/)。

機構 / recipient / consent 是受控結構化綁定，不新增任意全域 recipient 環境變數來繞過它。MQTT 本批沒有已實作的環境變數名稱，不自行列出假裝可部署的 broker 設定；待硬體 / broker 選定並另案核准後才定義。變數存在不證明功能可用。

## 5. MQTT 文件契約與下次審查

目前僅保留架構 §4.4 的概念欄位：可信 config 的 enabled、brokerRef、facilityBindings；binding 的 facilityId、deviceId、kind、allowedActions、commandTopicRef、stateTopicRef；命令的 commandId、deviceId、action、parameters、expiresAt。這些不是現成 API、程式或部署參數。

下次實作核准前須具備：

- 已查證硬體 / 協定與可信狀態來源；明確標記不支援的能力，不猜測 IR 指令。
- server 身分到 facility / device 的權限、白名單動作及機構核定 AC 設定界限；不接受任意 raw IR、topic、payload、URL 或 toggle。
- 每次確認綁命令、參數、身分、有效期；取消、換帳號、權限撤回即失效；LLM 不能自己確認或 publish。
- broker TLS / ACL、kill switch、非 retained 控制指令、過期 / 重連不重播與去重設計；隔離 commissioning 場域和人工接管。
- 設備狀態確認與 timeout / unknown 呈現；不得把 transport ACK 當設備成功。

在上述 checkpoint 完成前，不建 broker、不寫可執行 adapter、不接工具 catalog 或 live voice、不透過排程自動操作正式設備。

## 6. Owner 交付與 Review Gate

本文件完成後等待 owners 交付程式，不主動擴增實作範圍。交付需提供變更檔案清單、測試命令 / 實際結果、未完成事項；不可附秘密或 runtime 資料。

| Review 項目 | 核對重點 |
| --- | --- |
| 語言 owner | 明確命令與否定 / 引述 / 台語歌曲案例；手動 / 語音共用路徑；雙向偏好；revision / account-session generation；失敗不報已套用；不重複說話；無 SDK / model / transport / VAD 變動 |
| backend owner | LINE 預設停用且隔離；無 production call site；fake HTTP / resolvers 僅測試；無同意 / 未綁定零 outbound；內容最小化；timeout / 部分失敗 / 隔離去重 / redaction |
| 範圍稽核 | 未改 server.js、processCareAlert、既有 Telegram sender / cooldown / log、catalog；無 MQTT 程式、套件或 broker；未讀 env / runtime data |

執行測試前先檢查 imports / test setup 是否自動載入 env、runtime store 或啟動 server。若有，先回報並以隔離方式處理，不直接執行。功能單測通過不取代 iPhone 實機或正式授權資料來源驗收。

## 7. 後續啟用與停止門檻

### 本輪最終複核（2026-09-22，以此狀態為準）

- **CP-N1 CLOSED**：維持 architecture-agent 已重跑的 backend 34/34 結果；不重開既已結案問題。
- **CP-V1 CLOSED**：controller 以 `_languageSyncInFlight` 跟隨較新的同步結果，先檢查 session / account 失效，再等待有效的最新 ACK；背景分析不再僅因取代同步就讓 typed turn 提前放棄。兩種 analysis / ACK 排序測試均確認 conversation.item.create 與 response.create 各一次。
- **CP-V2 CLOSED**：恢復收音與失敗處理改用 isCapturingUserSpeech，包含 transcribing。成功保留 partial 並恢復 mic；timeout 取消該輪計時、清暫存字幕、回 idle，使用者可再按麥克風重試，不維持假收音狀態。這不是對實際音訊完整性的實機保證。
- architecture-agent 實際執行 `flutter test --no-pub test/voice_agent_controller_realtime_lifecycle_test.dart --plain-name CP-V`：**4/4 通過**，涵蓋 CP-V1 兩種排序與 CP-V2 ACK / timeout-retry。Copernicus 回報 **164 targeted tests 通過、靜態分析通過**；本次未獨立重跑全部 164 項或分析，與本次 4 項是重疊驗證，不加總。
- Main 回報 `flutter test --no-pub test/home_screen_layout_test.dart` **22/22 通過**，本次未獨立重跑。已檢查新增 widget 測試用 scrollUntilVisible 處理 lazy list、斷言離線 pending 不提前報 applied；settings 維持 profile setter、同步狀態呈現與 persistence 例外白話提示，未擴增功能。
- 已審閱 [iPhone smoke checklist](VOICE_LANGUAGE_SMOKE_CR0109.md)：清楚標示尚未實機執行，要求新 build、測試帳號及語言 / 字幕 / 收音 / 打字 / 換帳號驗證，不操作設備或傳送照護通知。
- **結論：本輪限定 code / tests review 收斂，未發現 CP-V1 / CP-V2 尚未解決的問題；不是 release approved。** 所有 iPhone / 真實音訊 / 台語品質未測；LINE 仍為隔離、預設停用且未接線模組，不能宣稱已可雙平台通知；MQTT 僅文件契約。CP-N2–CP-N7 保留作未來整合 checkpoint，本輪不擴大實作。下方待修文字為歷史紀錄，以本段結案狀態取代。

### CR-0109 隔離模組 Review Checkpoint（2026-09-22）

已唯讀審查 `caregiverNotificationDispatcher.js`、`facilityNotificationPolicy.js`、`lineNotifyService.js` 與 `caregiverNotificationDispatcher.test.js`。當次單測 31/31 通過；測試執行期間 owner 已補空 channels / 缺 binding refs 的安全處理、繁中最小訊息及台北時間測試。這是工作樹快照，不是凍結版本或 production 驗收。

- **CP-N1 / P2 / 待修正：audit 阻塞第二通道。** dispatcher 在 channel loop 內 await audit；注入永不 settle 的 audit 時，Telegram adapter 已回 accepted，但 LINE 不執行、dispatch 不結束。已用無網路的短時間競速探針重現。backend owner 應使 best-effort audit 不阻塞其他通道與回傳，補 hanging audit 測試；audit 故障不得重新發送。此修補限隔離模組與測試，不授權 production 接線。
- **CP-N2 / 整合前阻擋：有界執行與通道隔離。** resolver / adapter 也須有明確 timeout / cancellation 契約；一通道掛住不能永久擋另一通道。timeout 若可能已送出須為 unknown，不能標成確定 failed 後盲重送；單純 Promise.race 不會取消底層副作用，需驗證遲到結果與重複請求安全。
- **CP-N3 / 整合前阻擋：容量與去重生命週期。** 當前 Map 永不清除，達 maxEntries 後新事件持續 dispatcher_capacity；owner 已加註限制，不視為本批偷偷擴增 durable store 的授權。正式整合前另審容量監測、保留期 / durable dedupe 與操作處置；不得以清 Map / 重啟當安全恢復，也不得無界自動重送。
- **CP-N4 / 結果語義：** pending、accepted、unknown 的再次呼叫都回 skipped_duplicate，只表示此次未重送，不能推導原通知已送達。後續 consumer 必須保留原事件結果或另審具可追溯性的內部查詢契約；unknown 留待核對，不冒充 accepted。需補 pending / accepted / unknown 三種結果的獨立斷言。LINE 409 僅有 accepted-request-id 才當 accepted；HTTP 接受不代表已讀。
- **CP-N5 / 授權來源阻擋：** 現有 resolver 只是 interface / 預設 null，沒有可信 consent / facility / recipient production 來源。整合前驗證 scope 每一維度、撤回 / policy version / assignment 變更、同意查詢例外；不得原地重綁同一 bindingRef 到新目的地並沿用舊同意。event / policy 應有不可變快照或等價保護，避免 await 期間 caller 改動受檢資料。
- **CP-N6 / 時間與輸入：** 正式 event 須 server 產生穩定 identity 與帶時區時間；目前 Date.parse 的寬鬆接受不等於嚴格 ISO8601 契約。補無時區、非法日期、null / malformed event、未知通道、跨住民與各 consent scope 不匹配測試，定義不丟未捕捉例外的失敗結果。
- **CP-N7 / 接線門檻未解除：** 搜尋已檢查的 server / backend agent / services JS 路徑只見新模組互相引用，未見 production 呼叫；既有 Telegram 真 sender 未接此 dispatcher，測試中的 Telegram 是 fake adapter。目前不是可用的雙平台通知。LINE 仍隔離且預設停用；MQTT 仍僅文件契約。

首次結論：保留隔離實作範圍核准，CP-N1 需 owner 修正後複審；CP-N2 至 CP-N7 是後續整合 checkpoint，不能以單測替代。未修改 owner 的業務程式，未發真通知，未讀 env / runtime data。

### CP-N1 複核與 Voice 靜態 Review（2026-09-22）

- **CP-N1 CLOSED（取代上方待修正狀態）**：dispatcher 改為 detached Promise 呼叫 audit 並捕捉 rejection，已不 await audit。architecture-agent 實際重跑隔離 suite **34/34 通過**，包含 hanging / rejected / synchronous throws audit；兩 fake 通道結果可返回，沒有 unhandled rejection。這不是 durable audit 保證，程序終止仍可能丟失 best-effort 稽核。CP-N2–CP-N7 與 production 接線阻擋維持。
- **CP-V1 / P1 / 待修：背景 analysis 會使 typed turn 未送出。** `sendTextDuringRealtime` 在啟動 unawaited 陪伴分析後等待 `_synchronizeLanguage()`；若分析先於 session ACK 完成，分析的 `_synchronizeLanguage(result)` 增加 attempt 並可能取代 service context update，原等待回 false。typed caller 隨即清 turn / 回 idle / return true，未執行 sendUserText，外層卻被告知已接手。應將「同語言 context 被更新取代」與「語言真的失敗 / 帳號或 session 失效」分開，仍有效的 typed turn 等最新同步後僅送一次。補 analysis 先於 ACK、晚於 ACK、真的換帳號三種排序測試。
- **CP-V2 / P2 / 待修：transcribing 中切換後麥克風不恢復。** `_synchronizeLanguage` 記錄原 mic enabled 並 pause，但成功後只在 isAwaitingUserSpeech（ready / listening）恢復；transcribing 是既有有效收音狀態，卻被排除，resume flag 隨後清除，失敗分支也不退出此狀態。應明確處理正在收音時切換的成功 / 失敗策略，不丟已收音內容、不維持假收音 UI；補 transcribing + manual switch + ACK / timeout 測試。限語言同步狀態處理，不授權 VAD / commit 重構。
- 已檢查 settings 的 profile setter / sync message 接線，未在本輪 diff 找到另一個可獨立確認的新 bug；仍需 widget 狀態 / 儲存失敗測試。舊 taigiPreferred / manual taigi 顯示與帳號切換持久化應納驗收，不以此次靜態檢查宣稱已完成。
- Voice tests 仍由 owner 撰寫，本輪未執行 Flutter tests / build；上述兩項是具體程式路徑與事件排序的靜態發現，不宣稱實機重現。所有 iPhone、音訊、台語品質、通知送達與硬體均未實測。LINE 仍未接線，MQTT 仍僅契約。

正式通知整合另開 CR，先核准 consent / binding 權威來源、管理流程及精確 API / schema，再接兩平台共用 gate。僅於隔離測試完成、機構核對授權收件者、取得單獨的真實測試發送授權後，才安排不含住民敏感資料的受控發送驗收；本批不進行。

發現錯誤收件綁定、同意不可驗證或跨機構風險時停止受影響通道派送、撤銷綁定並由機構處理，保留最小稽核；不得以改送其他平台、關掉 consent gate 或假成功維持表面正常。若需停止現有 Telegram production 路徑，由負責維運者另行授權處理，本文件不暗中變更執行狀態。

本輪驗證僅文件一致性與 diff 格式；尚未審查 owners 最終程式、執行功能測試、發送通知或操作硬體。
