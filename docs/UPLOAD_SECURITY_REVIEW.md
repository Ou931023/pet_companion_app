# Multipart 與依賴安全修補 — 2026-10-07

## 契約與相容

Multer 固定 2.4.0，三個 parser 均限制 1 個檔案、8 個文字欄位、9 個 parts、100 字元欄位名稱、4096 bytes 欄位值、2 層 nesting、最大 array index 20。Busboy 在欄位值達到 4096 bytes 時標示 truncated，實測接受 4095、拒絕 4096；檔案大小與 parts 的 exact ceiling 可接受。這些是解析資源邊界，不是內容可信度或音訊身分驗證。

- STT：25,000,000 bytes，上游檔案轉錄 25 MB ceiling；未增加短錄音截斷。缺 key、provider 錯誤、空逐字稿與成功都清暫存；使用者中止時取消 provider request，先關 stream 再 unlink；不將 provider 原始例外傳給 client。
- 台語：預設 10 MiB，既有設定只接受正整數且最多 25 MB；保留音訊 MIME 與已知音訊副檔名的 octet-stream。
- 照片：8 MiB，保留 resident auth 在 parser 前及 task 所有權檢查；允許 JPEG/PNG/WebP/HEIC/HEIF MIME，與這些副檔名的 octet-stream。後者正是 Flutter `MultipartFile.fromPath` 預設序列化，推導 MIME 後交既有 verification。MIME/副檔名不是圖像內容驗證，AI 不確定仍須 `needs_review`。JSON fallback 成功 proof 仍保留，PostgreSQL 已保存或失敗則清暫存。

成功 response 不變；parse 拒絕回有限、去敏 400。尚未加入音訊 auth，避免破壞既有 build 8；既有 global IP limiter 仍在，但不宣稱正式 perimeter 或分散式防護已驗證。

## Fresh audit 與實際路徑

`npm audit --json` 和 `npm audit --omit=dev --json` 基線皆為 16：11 moderate、4 high、1 critical。Critical 是 `express → proxy-addr 2.0.7`，GHSA-jqcg-44mw-7w3h，涉及 IPv4-mapped IPv6 trust subnet。專案目前以 numeric hop 設 trust proxy；此設定不同於 advisory subnet 條件，但仍更新修補，不能推論任意 perimeter 已安全。

已更新相容版本：Express 4.22.3、body-parser 1.20.8、proxy-addr 2.0.8、qs 6.16.0、fast-uri 3.1.8、undici 7.30.0、@fastify/busboy 3.2.2、@grpc/grpc-js 1.14.5；不使用 `audit fix --force`。

修補後 runtime audit 剩 **8 moderate、0 high、0 critical**。剩餘根 advisory 是 Firebase Admin 的 Google Cloud 套件間接引入 uuid 9（GHSA-w5hq-g745-h8pq，v3/v5/v6 帶 buffer 的 bounds check）。查當前 gaxios、google-gax、teeny-request 呼叫點皆為 v4；本 App Firebase 包裝只用 auth，未接 Firestore/Storage API。這是目前暴露範圍判讀，不是零風險或正式執行覆蓋證據。npm 建議的完整解除需 Firebase Admin 14.x 主版本，本 PR 不做未经 provider 真機回歸的主版本強制升級，列為後續專案。CI 新增 runtime audit gate（high/critical 阻擋），moderate 仍須追蹤。

## 驗證與回復

本機合成 HTTP multipart、provider injection、bounded malformed/abort tests；不呼叫正式 provider、不傳住民內容、不建立警示。Flutter 測試實際 finalize 既有照片 request，確認 octet-stream、檔名、bytes 與 Bearer header。完整 check/test、CI 與部署 SHA 結果在 PR 記錄。

以本 PR 獨立 revert 回復；無 schema 或資料遷移。回復套件會恢復已知漏洞，若因相容性緊急回復，須保留風險記錄並重新準備安全修補。

來源：[Multer 2.4.0](https://github.com/expressjs/multer/releases/tag/v2.4.0)、[Multer limits](https://expressjs.com/en/resources/middleware/multer/#limits)、[field nesting advisory](https://github.com/advisories/GHSA-72gw-mp4g-v24j)、[array index advisory](https://github.com/advisories/GHSA-535w-7cp7-47q4)、[OpenAI file transcription](https://developers.openai.com/api/docs/guides/speech-to-text)、[proxy-addr advisory](https://github.com/advisories/GHSA-jqcg-44mw-7w3h)、[uuid advisory](https://github.com/advisories/GHSA-w5hq-g745-h8pq)。
