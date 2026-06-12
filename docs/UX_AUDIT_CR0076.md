# UX Audit — CR-0076 正式長者陪伴 App 體驗稽核

> 稽核日期：2026-06-12
> 性質：唯讀 audit / plan，本 CR 不改任何程式碼。
> 對應任務：`tasks/CR-0076-formal-elderly-companion-ux-audit.md`
> 範圍：Flutter 長者端、caregiver_web 管理端、backend instructions 組裝、docs、資產。

---

## 1. Executive Summary

整體判斷：**這個 App 已經是一個成立的長者陪伴 App，不是功能集合**。首次啟動流程（同意 → 登入 → 選寵物 → 命名 → 設定聯絡人 → 完成儀式 → 13 步導覽）完整且文案白話；Care Alert 從長者互動到 caregiver_web 的資料鏈路無斷點；Demo 文件與備援方案已存在。

Demo 前真正需要修的，集中在三類：

1. **錯誤訊息直出工程字串**（3 處，長者在現場可能直接看到 `FormatException: ...` 或 `sdpExchangeFailed`）— 這是唯一的程式碼 P0。
2. **Demo 帳號與資料準備**（預載金幣、清舊測試資料、預熱後端與台語 ASR）— 運維 P0，不用改 code。
3. **導覽結束後沒有第一步行動**、**寵物從不稱呼長者** — 最影響「陪伴感 vs 功能說明書」觀感的兩個缺口，建議展示前以小 CR 補。

Demo 前最該修的 3 件事：**CR-0079 錯誤訊息白話化（P0 程式修正）→ CR-0081 Demo 帳號與資料 seeding → CR-0082 Demo 排練（含預熱清單）**。其餘（金幣 rebalance、資產補幀、閒置互動）都可以 Demo 後再做。

---

## 2. App 核心價值判斷

對照「長者每天願意打開 → 願意互動 → 寵物建立陪伴感 → 自然產生照護資訊 → 長照中心提早掌握」五層價值鏈逐層檢查：

| 價值層 | 現況 | 判斷 |
|---|---|---|
| 每天願意打開 | 每日簽到（金幣+禮物）、寵物狀態每日衰減（不開 App 寵物會餓/心情下降）、分時段問候 | ✅ 成立，有日常回訪動機 |
| 願意互動 | 語音按鈕狀態文案清楚（「按住說話」「正在聽你說」）、打字備援、拼圖小遊戲 | ✅ 成立 |
| 寵物建立陪伴感 | 長期記憶引用規則良好（明確禁止「資料庫顯示」語氣）、問候會帶記憶、狀態文案溫暖（「就在這裡，靜靜陪著你」） | ⚠️ 部分成立 — 寵物**從不稱呼長者**，互動是單向的「你認識牠」而非「牠記得你是誰」 |
| 自然產生照護資訊 | 語音與打字共用同一情緒/風險分類引擎，medium 以上自動建 Care Alert，長者端無監視感 | ✅ 成立 |
| 長照中心提早掌握 | caregiver_web 四級風險看板 + 狀態機（new/acknowledged/resolved）+ Telegram high/urgent 推播（含 10 分鐘冷卻防洗版） | ✅ 成立 |

結論：價值鏈五層中四層成立，最弱的一環是「寵物記得你是誰」的人格化陪伴感（見 §8）。

---

## 3. P0 — Demo 前必修問題

### P0-1 例外字串直接顯示給長者（程式修正）

| # | 位置 | 現況 | 問題 |
|---|---|---|---|
| 1 | `lib/services/agent_router_service.dart:66` | `error.toString()` 直接成為使用者可見訊息 | 任何未捕捉例外（如 `FormatException: ...`）會原樣顯示在畫面上 |
| 2 | `lib/services/realtime_voice_service.dart:794,798` | fallback 文案「Realtime API 發生錯誤」；API 回傳的英文 message 可能直出 | 工程詞 + 英文訊息，Demo 時若連線異常會被全場看到 |
| 3 | `lib/screens/settings_screen.dart:890` | 顯示 `lastFailure.name`（Dart enum 名，如 `sdpExchangeFailed`） | 已有白話的 `.message` extension 卻沒用上，一行可修 |

→ 歸入 **CR-0079**。注意 #2 的 `realtime_voice_service.dart` 是 🔒 邊界檔案，需 architecture-agent 核准、由 realtime-voice-agent 主導，且只改「錯誤文案層」不動連線流程。

### P0-2 Demo 帳號與資料未 seeding（運維，不改主流程）

- Demo 帳號（`default_user`）金幣、寵物狀態、簽到、皮膚全存本機 SharedPreferences（`lib/services/local_storage_service.dart:34-47` 用全域 key）。**換一支展示機就歸零**：金幣回到 100、導覽重新觸發、記憶問候是空的。
- caregiver_web 若殘留舊測試 Care Alert / 訂單，老師會看到雜訊。
- → 歸入 **CR-0081**：Demo 機上預跑一次帳號初始化（含預載金幣約 300、預先解鎖一隻備用皮膚、預建 2–3 筆有層次的 Care Alert 範例資料、預存幾筆長期記憶讓問候有內容）。

### P0-3 Demo 當天運維風險未演練成肌肉記憶（流程）

- Render 冷啟動 30–60 秒、台語 ASR 首次推論約 20 秒、Telegram 冷卻 10 分鐘 — 文件（`docs/DEMO_SCRIPT.md`）都寫了，但需要實際彩排一次含「備援切換」。
- → 歸入 **CR-0082**（docs-only + 排練）。完整風險表見 §11。

> 補充：本次稽核**沒有發現**導覽流程卡死、跨頁死路、debug/demo 字樣外露等 P0 級 UI 問題。導覽有元件找不到時的降級機制（`lib/onboarding/coach_mark_overlay.dart:207-217`），不會 crash。

---

## 4. P1 — 建議展示前修

| # | 問題 | 位置 | 說明 |
|---|---|---|---|
| P1-1 | 導覽結束後沒有「第一步行動」 | `lib/onboarding/coach_mark_overlay.dart:322-326` | 13 步看完點「開始使用」就回首頁，長者站在原地不知道先做什麼。建議導覽結束直接引導第一次互動（見 §6） |
| P1-2 | 寵物不會稱呼長者 | backend `buildRealtimeInstructions`（`backend/stt_proxy/server.js:371-408`）；onboarding 無稱呼欄位 | 系統沒收集使用者稱呼，prompt 只有寵物名字。最小修法：onboarding 加一步「想讓牠怎麼叫你？」並帶進 instructions（跨 frontend + companion-memory 邊界，需走 CHANGE_REVIEW） |
| P1-3 | 任務/獎勵發生時寵物沒有可見開心反應 | `lib/controllers/pet_stats_controller.dart`（只改數值，無動畫） | 完成任務/簽到後只有 SnackBar 與數字變化，寵物本體無反應。最小修法：复用既有狀態圖切到 `excited`/`happy` 數秒 + 「+親密度」浮動字（比照金幣動畫 `lib/widgets/coin_badge.dart` 已有的模式） |
| P1-4 | agent router 錯誤訊息工程詞 | `lib/services/agent_router_service.dart:57,64` | 「agent route failed: 500」「agent route timeout」→ 白話化（與 P0-1 同 CR 一起修） |
| P1-5 | 金幣用途說明不完整 | 導覽 Step 9 只說「解鎖外觀」 | 商城食物/玩具/復活藥水都吃金幣但導覽沒提；長者可能不知道金幣還能照顧寵物 |
| P1-6 | 「每日簽到」雙入口混淆 | 簽到日曆（`lib/screens/home_screen.dart:688-760`）與任務清單各有一個簽到 | 兩處可觸發，長者可能搞不清差別。Demo 講稿先統一只示範日曆入口 |
| P1-7 | Demo 帳號展示經濟太緊 | 初始 100 金幣，換皮 60/80 | 現場想示範「換皮 + 買東西餵寵物」會不夠用 → CR-0081 預載解決，不改正式數值 |

---

## 5. P2 — 加分優化（Demo 後再做）

| # | 問題 | 位置 | 說明 |
|---|---|---|---|
| P2-1 | 天竺鼠 talk 動畫只有 3 幀（狗/狐狸 6 幀） | `lib/utils/asset_paths.dart:7-26`、`assets/pets/talk/` | 同 220ms/幀下天竺鼠說話動作明顯比較「卡」。Demo 時先用狗或狐狸展示即可 |
| P2-2 | 閒置時寵物不會主動說話 | 無此機制 | 進場問候後就安靜等待；可加「閒置 N 分鐘輕聲關心一句」（注意別變成騷擾） |
| P2-3 | 對話延續感只靠記憶抽取 | `lib/screens/home_screen.dart:77-83` | 重開 App 不顯示上次對話脈絡，若上次內容沒抽成記憶就完全遺忘 |
| P2-4 | 金幣/寵物狀態無後端同步 | `lib/services/local_storage_service.dart` | 換裝置歸零、可被本機篡改。正式營運需求，Demo 不影響（單機展示） |
| P2-5 | 經濟中期飽和 | 見 §7 | 兩隻換皮共 140 金幣，一～兩週全解鎖後金幣無處花 |
| P2-6 | 復活藥水太便宜（150） | `lib/services/shop_service.dart:159-167` | 死亡機制形同虛設；但 Demo 期間反而是優點（不會翻車） |
| P2-7 | caregiver_web 可能直出 `err.message` | `caregiver_web/app.js:2929` | 有 fallback 但模式有風險，建議列舉已知錯誤狀態 |
| P2-8 | iOS ATS 全開（`NSAllowsArbitraryLoads`） | `ios/Runner/Info.plist:44-47` | Demo 可接受，上架前須收斂（已有 CR-0054 追蹤） |
| P2-9 | 商城物品分類不清（食物/玩具/照護混排） | `lib/services/shop_service.dart:24-169` | 長者難判斷買什麼最划算，可加分類分區 |

---

## 6. 新手導覽缺口與文案建議

### 現況

13 步 coach mark（`lib/onboarding/coach_mark_keys.dart:56-146`）文案全白話、無工程語，可從設定頁與首頁「使用教學」按鈕重看 — 基礎很好。但定位偏「功能說明書」：逐一介紹元件，缺少「現在先做這個」的行動邀請；結束後直接回首頁，沒有第一個任務或寵物的第一句話。

### 缺口與建議文案

| 缺口 | 建議（最小改法） |
|---|---|
| 導覽結束無行動引導 | 最後一步改為行動邀請：「都認識了！現在按住下面的麥克風，跟〔寵物名〕說第一句話吧，說『你好』就可以了。」結束後語音按鈕加一次性呼吸光圈提示 |
| 寵物沒有「第一句開場白」 | 導覽結束觸發一次特別問候：「〔長者稱呼〕你好，我是〔寵物名〕！以後我每天都在這裡陪你。你今天過得好嗎？」（依賴 P1-2 的稱呼收集） |
| 金幣用途說明不完整 | Step 9 文案補充：「上面這些金幣，可以幫牠換新樣子，也可以在商城買點心和玩具照顧牠。」 |
| 任務好處沒講 | 若今日任務維持隱藏（CR-0056 B2 決策），導覽不需提；若 Demo 要展示任務，需先恢復入口並在導覽補一步「完成今天的小任務，〔寵物名〕會更開心，也會給你金幣」 |
| 語音按鈕互動方式只在導覽講一次 | 維持現況可接受（按鈕本身有「按住說話」動態標籤）；可選：首次進首頁在按鈕上加一次性「按住我說話」氣泡 |

---

## 7. 金幣與黏著度機制建議

### 目前 Economy Map

**來源**（每日理論上限約 40–70）：

| 來源 | 數值 | 位置 |
|---|---|---|
| 初始金幣 | 100 | `lib/models/user_profile.dart:50` |
| 每日簽到 | 一般日 10–25、週一 25–40，+5 親密度；每月 4 的倍數日附小禮物 | `lib/models/daily_reward.dart:58-82` |
| 今日任務 ×5（簽到/喝水/吃飯/心情/休息） | 10/5/6/5/4 金幣，各 +1~+3 親密度 | `lib/controllers/task_controller.dart:23-57` |
| 拼圖遊戲 | 3×3=5、4×4=8 金幣 | `lib/controllers/puzzle_game_controller.dart:144-147` |
| 聊天/語音互動 | **0 金幣**（只 +2 親密度 +2 心情） | `lib/controllers/pet_stats_controller.dart:34-37` |

**用途**：換皮 狗 0 / 天竺鼠 60 / 狐狸 80（`lib/models/pet_skin.dart:40-44`）；商城食物 20–70、玩具/用品 45–120、復活藥水 150（`lib/services/shop_service.dart`）。

**寵物狀態**：親密度初始 30（每日 -5，≤0 寵物沉睡）、飽足 50（-8/日）、心情 60（-5/日）；衰減一次性不跨日累計（`lib/controllers/pet_stats_controller.dart:75-96`）。

### 問題點

1. 換皮全解鎖只要 140 金幣 ≈ 一～兩週，之後金幣只剩商城消耗，中期目標斷層。
2. 拼圖（耗時最長的互動）獎勵最低，性價比倒掛。
3. 聊天/語音（本 App 核心行為）沒有金幣回饋 — 機制鼓勵「刷任務」多於「真互動」。可接受刻意不給（避免功利化陪伴），但至少要有寵物的情感回饋（P1-3）。
4. 任務完成 → 寵物變開心，數值上成立、視覺上看不到。

### Demo 前最小數值調整（不破壞正式版）

**原則：不改正式數值常數，只做 Demo 帳號資料 seeding（CR-0081）。**

| 項目 | 建議 |
|---|---|
| Demo 帳號預載金幣 | **300**（夠現場示範：解鎖一隻換皮 80 + 買點心餵食 40 + 剩餘看得到餘額變化） |
| Demo 帳號寵物狀態 | 親密度 ~60、飽足 ~40（偏餓，方便示範「餵食 → 變開心」）、心情 ~70 |
| Demo 換皮價格 | **不降價** — 預載金幣已解決，避免分支邏輯 |

### Production-friendly 數值建議（Demo 後，CR-0078）

| 項目 | 現值 | 建議 | 理由 |
|---|---|---|---|
| 初始金幣 | 100 | 維持 100 | 第一週內解鎖第一隻換皮，建立早期成就感 |
| 每日簽到 | 10–25（週一 25–40） | 一般日 8–15；改「連續簽到」遞增（第 7 天 +20） | 把隨機性換成連續性，獎勵每天回來而非偶爾回來 |
| 任務獎勵 | 4–10/項 | 維持；全完成加「全勤 +10」 | 鼓勵完成整組而非挑高分項 |
| 聊天/語音互動 | 0 | 維持 0 金幣，但補寵物情感回饋（動畫+語句） | 陪伴不該功利化 |
| 拼圖 | 5/8 | 簡單 8 / 困難 15 | 對齊時間投入 |
| 換皮價格 | 60/80 | 新增第二層外觀 150–250（節日裝等） | 建立月級目標；既有價格不動以免懲罰早期使用者 |
| 復活藥水 | 150 | 250–300 | 讓照顧疏忽有重量，但不至於絕望 |
| 每日獲得上限 | 無明確上限（實際 ~70） | 軟上限 ~60/日 | 防刷、控通膨 |
| 週獎勵 | 無 | 建議加：一週完成 5 天簽到 → 週日禮物盒 | 形成週節奏，對長者是「每週的小期待」 |

---

## 8. 陪伴感強化建議

做得好的（保持）：記憶引用規則明確自然（`backend/stt_proxy/services/memory/memoryContextService.js:89-108` 明文禁止「我查到你的記憶」）；分時段問候且優先帶高品質記憶；狀態文案溫暖（`lib/widgets/pet_status_panel.dart:22-28`，「〔名字〕就在這裡，靜靜陪著你」是全 App 最有陪伴感的一句）。

缺口（依影響排序）：

1. **寵物不知道長者是誰**（P1-2）。所有問候都是「你之前說…」，從不喊名字。最小修法：onboarding 加「想讓牠怎麼稱呼你」一步（選填，預設不稱呼），存 profile 並帶進 `buildRealtimeInstructions` 與 greeting 模板。這是單點修改、跨 frontend-ux + companion-memory 兩個 agent 邊界，需在 `docs/CHANGE_REVIEW.md` 開提案。
2. **行為與表情斷鏈**（P1-3）。8 種狀態圖（happy/excited/caring…）齊全，但任務完成、簽到、收禮時寵物表情不變。复用既有資產做 3 秒的狀態切換即可，不需要新圖。
3. **閒置沉默**（P2-2）。問候完就安靜。可後續加「閒置 10 分鐘輕聲一句」，但要節制、可關閉。
4. **動畫一致性**（P2-1）。補天竺鼠 talk 04–06 三張圖，或暫時把天竺鼠幀率調慢對齊觀感。

---

## 9. 長照中心工作流建議

**結論：工作流成立，可直接演示。** 資料鏈路全程打通：Flutter 情緒/對話 → backend 同一分類引擎（語音與打字共用）→ medium+ 建 Care Alert 入 PostgreSQL → caregiver_web RBAC 過濾呈現 → high/urgent 加推 Telegram（10 分鐘冷卻）。狀態機 new → acknowledged → resolved 完整且含稽核 log（`backend/stt_proxy/server.js:689-742`）。

展示建議（不改 code）：

1. **預埋有層次的範例資料**（CR-0081）：一筆 urgent（疑似跌倒）、一筆 high（連日情緒低落）、一筆 medium（睡眠異常），讓看板一眼呈現分級價值，而不是只有現場觸發的單筆。
2. **演示「處理閉環」**：現場示範把 new 標成 acknowledged，講「照護人員看到、認領、處理完銷案」的故事 — 這是「減少巡查負擔」的最直接證據。
3. **講稿強調「不是監視」**：長者端全程只有陪伴語氣，風險分析在後台 — 這正好對應評審最可能質疑的倫理問題。
4. Telegram 冷卻 10 分鐘：彩排時若已觸發過同級別通知，現場可能收不到第二次 — 備援是切到 caregiver_web 看板（已寫入 DEMO_SCRIPT，需排練）。

---

## 10. 錯誤訊息白話化建議

良好範本（已達標，可作標準）：Auth（`lib/controllers/auth_controller.dart`「Email 或密碼不太對」）、Marketplace（完整錯誤碼→白話對照表）、語音按鈕全狀態文案、麥克風權限文案（「我聽不到你的聲音耶，請到手機設定打開麥克風權限…」）。

需修清單（全部歸入 CR-0079）：

| 位置 | 目前 | 建議文案 |
|---|---|---|
| `agent_router_service.dart:66` | `error.toString()` | 「我這邊有點小狀況，等一下再跟我說一次好嗎？」 |
| `agent_router_service.dart:57` | `agent route failed: 500` | 「現在連線比較慢，請稍等一下，或等會再試一次。」 |
| `agent_router_service.dart:64` | `agent route timeout` | 「我想得有點久，我們再試一次好嗎？」 |
| `realtime_voice_service.dart:794` | `Realtime API 發生錯誤` | 「聲音連線不太穩，我們正在幫你重新連接。」 |
| `realtime_voice_service.dart:798` | API 英文 message 直出 | 一律映射為上句白話文案，原始訊息只進 debug log |
| `settings_screen.dart:890` | `lastFailure.name`（enum 名） | 改用既有 `.message` extension（一行修正） |
| `caregiver_web/app.js:2929` | 可能直出 `err.message` | 列舉已知狀態，未知一律「儲存沒有成功，請稍後再試。」（管理端，P2） |

文案準則（沿用 CLAUDE.md）：說白話原因 + 給下一步 + 不嚇人 + 無工程詞 + 不讓長者覺得自己做錯。

---

## 11. Demo 翻車風險表

| # | 風險 | 等級 | 發生原因 | 預防措施 | 現場備援操作 | 現場備援說法 |
|---|---|---|---|---|---|---|
| 1 | Render 冷啟動，第一個請求卡 30–60 秒 | P0 | free tier 15 分鐘閒置即休眠 | 開講前 10 分鐘打 `/health` 預熱，開講前 2 分鐘再打一次 | 邊講系統架構邊等；切打字聊天暖場 | 「系統正在喚醒，我先介紹一下架構」 |
| 2 | 場地 Wi-Fi 不穩，WebRTC 連不上 | P0 | 會場網路限制 UDP/STUN | 事前用手機熱點全流程彩排；Demo 機預設熱點 | 切手機熱點重連（按鈕會顯示「正在重新連線」） | 「現場網路比較擁擠，我們換個網路」 |
| 3 | 連線異常時畫面跳出工程字串 | P0 | P0-1 三處 exception 直出 | **Demo 前完成 CR-0079** | 快速關閉提示，改示範打字聊天 | （修掉後不需要） |
| 4 | OpenAI key 失效 / 額度用盡 | P0 | 帳務或 quota | 前一天確認 `/health` 回 `hasOpenAiKey:true`；當天早上實測一輪語音 | 切打字聊天（同引擎）；播彩排錄影 | 「我們看一下昨天彩排的完整畫面」 |
| 5 | 麥克風權限被拒或重置 | P1 | iOS 更新/重裝後權限重置 | 開講前實測一句語音 | 設定→App→開麥克風（文案已白話引導） | 「手機保護隱私把麥克風關了，打開就好」 |
| 6 | 台語 ASR 首次推論 ~20 秒 | P1 | 模型冷啟動 | 開講前打 `/api/asr/taigi/warmup` 與 status 檢查 | 先講台語功能介紹，等暖機完再示範；或先示範國語 | 「台語模型正在熱身，先聽牠講國語」 |
| 7 | 環境吵雜、辨識亂跳 | P1 | 會場底噪 | 準備領夾麥/靠近手機講；測試句庫選短句 | 改用打字聊天（功能等價，同樣觸發 Care Alert） | 「現場比較熱鬧，我用打字示範一樣的功能」 |
| 8 | Telegram 通知沒到（冷卻 10 分鐘內重複觸發） | P1 | 彩排時已觸發同級別通知 | 正式 Demo 前 10 分鐘不要觸發 high/urgent；換不同測試句 | 切 caregiver_web 照護提醒分頁（資料一定在） | 「通知有防洗版機制，我們直接看管理端」 |
| 9 | Demo 機本機資料不對（金幣 100、導覽重跳、記憶空白） | P1 | 金幣/狀態/導覽旗標全在 SharedPreferences，換機即重置 | **CR-0081**：正式 Demo 機上預跑 seeding 並全流程走一遍 | 跳過受影響環節，講稿補位 | 「這台是全新帳號，正好看一下新手流程」 |
| 10 | caregiver_web 殘留舊測試資料 | P1 | 彩排產生的 alert/訂單沒清 | Demo 前清場 + 預埋 3 筆有層次的範例（CR-0081） | 用過濾器只看當天 | — |
| 11 | Admin Token 當眾外洩 | P1 | 現場輸入被投影 | 開講前先貼好 token；絕不當眾輸入或開 .env | 若外洩，會後立即輪替 | — |
| 12 | production build 帶錯 `--dart-define`，連到 localhost | P1 | build 指令打錯 | 照 DEMO_SCRIPT 指令 build；App 有守門畫面（`app_config.dart:154-159`）會擋下而非靜默壞掉 | 重 build（需預留時間，前一晚完成並驗證） | — |
| 13 | DB 連線失敗，記憶/alert 存不進去 | P1 | Render PG 偶發 | `/health` 檢查含 DB；通知設計為 DB 失敗不阻擋（已防守） | 示範語音對話本體（不依賴 DB 寫入成功） | 「資料稍後會補上，先看互動」 |
| 14 | 寵物處於「沉睡」（親密度 0）開場 | P2 | Demo 帳號久未開、衰減觸發 | seeding 時把親密度設 ~60；當天早上開一次 App 確認 | 現場買復活藥水（反而是賣點） | 「太久沒陪牠，牠在睡覺 — 這就是養成感」 |
| 15 | Firebase 初始化卡住 | P2 | 網路擋 Firebase | 已防守：3 秒 timeout + fallback（`lib/main.dart:15-17`） | 無需操作 | — |

---

## 12. 後續 CR 拆分建議

| CR | 名稱 | 必要性 | 時機 | 範圍與負責 agent |
|---|---|---|---|---|
| **CR-0079** | Elderly Friendly Error Message Polish | **必要（P0）** | Demo 前 | §10 全部 7 處文案。`agent_router_service.dart` + `settings_screen.dart` 小修；`realtime_voice_service.dart` 兩行文案需 architecture-agent 核准、realtime-voice-agent 執行（只改文案層，不碰連線流程）。補對應單元測試 |
| **CR-0081** | Demo Account and Data Seeding | **必要（P0 運維）** | Demo 前 | Demo 機 seeding：金幣 300、寵物狀態（親密 60/飽足 40/心情 70）、預存記憶、caregiver_web 清場 + 預埋 3 筆分級 alert。優先做成手動 SOP 文件 + 必要時一支不進 git 的 seed script，**不改 App 邏輯** |
| **CR-0082** | Demo Script Final Rehearsal | **必要（P0 運維）** | Demo 前 | docs-only：把 §11 風險表併入 DEMO_SCRIPT 檢查清單，完整彩排一次（含熱點切換、打字備援、Telegram 冷卻情境） |
| **CR-0077** | Onboarding Companion Journey Polish | **建議（P1）** | Demo 前（若時間允許）；至少做導覽結尾行動引導 | 兩個子項可拆：(a) 導覽最後一步改行動邀請 + 結束後寵物第一句問候（frontend-ux-agent，小改）；(b) 收集長者稱呼並帶進 instructions（跨 frontend + companion-memory + backend，需 CHANGE_REVIEW 提案，可 Demo 後做） |
| **CR-0078** | Coin Economy and Pet Progression Rebalance | **可緩（P2）** | Demo 後 | §7 production 數值表 + 任務完成寵物動畫回饋（P1-3 可提前抽出與 CR-0077(a) 同批做）。長期含金幣後端同步（需 architecture-agent 規劃，動 DB schema） |
| **CR-0080** | Pet Asset Finalization | **可緩（P2）** | Demo 後 | 補天竺鼠 talk 04–06 幀；Demo 用狗/狐狸即可規避 |

執行順序建議：**CR-0079 → CR-0081 → CR-0077(a) → CR-0082（彩排收尾）**，其餘 Demo 後。

---

## 附：驗收標準快答

1. **為什麼長者每天回來？** 每日簽到獎勵 + 寵物狀態會衰減（牠需要你）+ 分時段帶記憶的問候。機制成立。
2. **哪裡降低黏著度？** 中期金幣飽和（§7）、任務完成無寵物可見反應（P1-3）、寵物不認得你（P1-2）。
3. **金幣與養成哪裡要調？** Demo 前只做帳號 seeding；正式版照 §7 表（連續簽到、週獎勵、第二層外觀、復活漲價）。
4. **新手導覽缺什麼？** 不缺說明、缺行動：結尾沒有「現在先做什麼」與寵物第一句話（§6）。
5. **長照人員能減負擔嗎？** 能：分級看板 + 處理閉環 + 只推 high/urgent 的通知設計，鏈路無斷點（§9）。
6. **Demo 最可能翻車的點？** 冷啟動、現場網路、工程錯誤字串直出、Demo 機本機資料重置（§11 #1–#4、#9）。
7. **Demo 前最該修的 3 件事？** CR-0079 錯誤訊息、CR-0081 seeding、CR-0082 彩排。
8. **哪些可以 Demo 後再做？** CR-0078 經濟 rebalance、CR-0080 資產補幀、CR-0077(b) 稱呼收集、閒置互動、金幣後端同步。
