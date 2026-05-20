# 台語短錄音 Demo 操作流程

今天 demo 目標是跑完：

iPhone App -> 台語短錄音 -> Mac 後端 `/api/asr/taigi` -> 顯示「台語辨識中，請稍等」-> 顯示「我聽到的是：xxx」-> 使用者按「送出」-> AI 寵物用台語語境回覆。

## 1. 查 Mac 區網 IP

```bash
ipconfig getifaddr en0
```

如果這個指令沒有回傳 IP，請到 macOS Wi-Fi 設定查看目前 Wi-Fi 的 IP 位址。

## 2. 啟動後端

```bash
cd backend/stt_proxy
HOST=0.0.0.0 PORT=3001 npm start
```

iPhone 和 Mac 必須在同一個 Wi-Fi。後端要綁在 `0.0.0.0`，不要只綁 `127.0.0.1`，手機才連得到。

## 3. iPhone Safari 測狀態

在 iPhone Safari 開：

```text
http://<Mac區網IP>:3001/api/asr/taigi/status
```

看到 JSON 回應即可，App 內只會顯示友善狀態文字，不會顯示 raw JSON。

## 4. 可選 warmup

```bash
curl -X POST http://<Mac區網IP>:3001/api/asr/taigi/warmup
```

Warmup 只檢查環境與 dry-run，不是 streaming，也不是常駐 Python worker。正式辨識仍可能需要約 20 秒上下。

## 5. Flutter 實機執行

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://<Mac區網IP>:3001
```

如果從 App 設定頁手動填後端 URL，請填完整 STT proxy URL：

```text
http://<Mac區網IP>:3001/api/stt/transcribe
```

## 6. App 內操作

1. 設定頁 -> 語音輸入方式 -> 台語短錄音
2. 回首頁
3. 按語音按鈕
4. 說一句短句
5. 再按一次結束錄音
6. 等待「台語辨識中，請稍等」
7. 出現「我聽到的是：xxx」
8. 按「送出」
9. 看 AI 寵物回覆

送出後，對話紀錄應寫入：

- `languageHint = taigi`
- `asrSource = taigi-asr`
- `routeReason = taigi_asr_transcript`
- `replyLanguage = mixed-zh-taigi`

## 7. 今日建議測試句

先講短句、靠近麥克風、背景安靜：

- 心情無好
- 今仔日無好
- 我有點無聊
- 睏袂去
- 家裡攏無人

先避免：

- 太長的句子
- 背景很吵的錄音
- 離麥克風太遠
- 一次講很多情緒與事件

## 8. 現場注意

- 第一次模型推論可能比較慢。
- `confidence` 目前視為 unavailable，App 不顯示信心分數。
- 如果 App 顯示台語語音辨識暫時無法使用，先用 iPhone Safari 打開 status endpoint 確認手機是否連得到 Mac。
- 不要同時啟動 Realtime 即時語音與台語短錄音。
