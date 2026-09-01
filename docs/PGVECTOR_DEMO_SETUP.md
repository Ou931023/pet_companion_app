# PostgreSQL + pgvector Demo 啟動指南

> 目標：Demo 當天讓長期記憶**實際跑 PostgreSQL + pgvector**，而不是 JSON fallback。
> 照著本文件操作即可，**不需要改任何程式碼**。

---

## 1. 前提說明

- **不需要改程式碼。** 記憶系統已內建「DB 優先、JSON fallback」的自動切換。
- 系統會在以下三個條件**同時成立**時，自動走 pgvector：
  1. `DATABASE_URL` 有設定
  2. `PGVECTOR_ENABLED=true`
  3. PostgreSQL 實際可連線（後端啟動時會做一次 `SELECT 1` 健檢，逾時預設 2 秒）
- 只要任一條件不成立（沒設 env、DB 沒起、連不上），系統會**自動 fallback 到 JSON**，
  讀寫 `backend/stt_proxy/data/companion_memories.json`，**不會 crash**。
- DB 與 JSON 是**兩個獨立的儲存**，切換不會互相覆蓋或刪除資料。

相關程式位置（僅供參考，不需修改）：
- 連線與閘門：`backend/stt_proxy/db/postgres.js`（`getPool` / `isPostgresAvailable`）
- 記憶讀寫 + 向量查詢：`backend/stt_proxy/services/memory/memoryStore.js`（`::vector`、`<=>` cosine）
- 容器定義：`backend/stt_proxy/docker-compose.yml`
- migration runner：`backend/stt_proxy/db/migrate.js`

---

## 2. 啟動步驟

所有指令都在 `backend/stt_proxy/` 目錄下執行：

```bash
cd backend/stt_proxy
```

### 2.1 啟動 pgvector container

```bash
docker compose up -d db
docker compose ps          # 等 STATUS 出現 healthy 再繼續
```

- service 名稱：`db`，container 名稱：`pet_companion_db`，image：`pgvector/pgvector:pg16`
- 對外 port：`5432`
- 資料庫 `love_companion` 由容器**自動建立**，不需手動 createdb

### 2.2 設定必要環境變數

把下列 key 設進 `backend/stt_proxy/.env`（值請自行填寫，見第 3 節）。
**server 端要走 DB，`DATABASE_URL` 與 `PGVECTOR_ENABLED` 兩者缺一不可。**

### 2.3 執行 migration

```bash
npm run db:migrate         # 看到「[DB] migrations completed」即成功
```

- 會先建立 `vector` / `pgcrypto` extension，再依序套用 `db/migrations/001~007`
- 主記憶表 `companion_memories`（含 `embedding VECTOR(1536)` 與 HNSW 索引）由 `004` 建立
- 全部 migration 皆為 `IF NOT EXISTS`，可重複執行

### 2.4 啟動 backend

```bash
npm start                  # 等同 node server.js（預設 PORT 3001）
```

- 啟動 log **不應**出現 `using JSON fallback`

### 2.5 啟動 Flutter app

在專案根目錄：

```bash
flutter run                # iOS 實機 / 模擬器
```

- App 透過設定中的 STT Proxy URL 連到上面的 backend（預設 `http://<你的後端主機>:3001`）。
- 確認 App 設定頁的後端位址指向**這台跑著 PostgreSQL 的 backend**。

---

## 3. 必要環境變數（只列 key，請勿把真實值貼給任何人 / 寫進文件）

| key | 是否必須 | 說明 |
|---|---|---|
| `DATABASE_URL` | **必須** | 必須由執行環境明確提供；migration 與 server 都不再內建帳密。production 缺少時會 fail-fast，且不得退回 JSON。 |
| `PGVECTOR_ENABLED` | **必須＝`true`** | 雙重閘門之一；不是 `true` 一律走 JSON fallback。 |
| `OPENAI_API_KEY` | 非必須、**建議設** | 不設仍可走 DB，但 embedding 會退成 deterministic mock（語意檢索品質下降）。要真語意搜尋就要設。 |
| `EMBEDDING_MODEL` | 選用 | 預設 `text-embedding-3-small`（1536 維，與 schema 相符），通常不用動。 |
| `PG_POOL_MAX` / `PG_IDLE_TIMEOUT_MS` / `PG_CONNECTION_TIMEOUT_MS` | 選用 | 皆有預設（10 / 30000 / 2000ms），Demo 不用設。 |

> migration 與後端都需要明確的 `DATABASE_URL`；不提供時必須失敗，不能使用內建本機密碼或把 JSON fallback 當正式資料庫。

---

## 4. 驗證指令

```bash
# (1) container 有在跑 + 健康
docker compose ps
docker exec pet_companion_db pg_isready -U postgres -d love_companion

# (2) PostgreSQL 可連線 + vector extension 已啟用
docker exec -it pet_companion_db psql -U postgres -d love_companion -c "\dx"
#   應在清單看到 vector

# (3) companion_memories table 與 embedding 欄位存在
docker exec -it pet_companion_db psql -U postgres -d love_companion -c "\d companion_memories"
#   應看到 embedding | vector(1536)

# (4) backend 沒有走 fallback
#   觀察 backend 啟動 / 運作 log，不應出現：
#   [postgres] unavailable, using JSON fallback

# (5) memory API 回傳 provider = postgres_pgvector（PORT 預設 3001）
curl -s "http://localhost:3001/api/memories?userId=default_user" | grep -o '"provider":"[^"]*"'
#   期望：postgres_pgvector （若是 json_fallback 代表還在走 JSON）

# (6) 新增一筆記憶後，資料真的進 PostgreSQL（不是 JSON 檔）
#   先記下目前筆數
docker exec -it pet_companion_db psql -U postgres -d love_companion -c "SELECT count(*) FROM companion_memories;"
#   在 App 裡跟寵物說一句會被記住的話（例如「我女兒週末會回來」），稍候再查一次：
docker exec -it pet_companion_db psql -U postgres -d love_companion -c "SELECT count(*), max(created_at) FROM companion_memories;"
#   筆數應 +1；同時 backend/stt_proxy/data/companion_memories.json 的修改時間「不應再變動」
```

---

## 5. 疑難排解（DB 連不上怎麼辦？）

### 快速判斷現在是 DB 還是 JSON
- backend log 出現 `[postgres] unavailable, using JSON fallback` → 正在走 JSON。
- `/api/memories` 的 `provider` 欄位是 `json_fallback` → 正在走 JSON；是 `postgres_pgvector` → 正在走 DB。

### 常見錯誤與解法
| 症狀 | 可能原因 | 解法 |
|---|---|---|
| `provider=json_fallback` / log 出現 `using JSON fallback` | `PGVECTOR_ENABLED` 不是 `true`、`DATABASE_URL` 沒設、或 DB 連不上 | 檢查兩個 env；確認 `docker compose ps` 為 healthy |
| `password authentication failed` | `DATABASE_URL` 帳密與 compose 不符 | 帳密要對齊 compose（預設 `postgres` / `password`） |
| `database "love_companion" does not exist` | 資料卷是舊的、曾用不同 DB 名 | `docker compose down -v` 清卷再 `up -d`（會清空 DB 資料） |
| `relation "companion_memories" does not exist` | 沒跑 migration | `npm run db:migrate` |
| `extension "vector" is not available` | 用到非 pgvector 的 image | 確認 image 為 `pgvector/pgvector:pg16`（compose 已設） |
| `port 5432 already in use` | 本機已有其他 PostgreSQL | 停掉它，或改 host port |

### DB 連不上時的回退（fallback）
- **不用做任何事就會自動回退**：後端連不上 DB（2 秒逾時）會自動改走 JSON，Demo 不會中斷。
- 若想明確強制走 JSON：把 `PGVECTOR_ENABLED` 設為非 `true`（或移除 `DATABASE_URL`）後重啟 backend。
- **回退時不要刪除 `backend/stt_proxy/data/companion_memories.json`**——它就是安全網。
- 注意：DB 與 JSON 各自獨立，切換不會搬移既有資料；切到 DB 後 DB 是全新（空的）store。

### 為什麼需要 fallback？
- Demo 當天若 DB / 容器 / 網路出狀況，fallback 能讓記憶功能**即時頂上、不 crash、不中斷展示**。
- 它是內建、非破壞性的安全網，建議**保留**，不要為了 Demo 把它拿掉。

---

## 6. 一句話總結

> 起容器 → 設 `DATABASE_URL` + `PGVECTOR_ENABLED=true`（建議再加 `OPENAI_API_KEY`）→ `npm run db:migrate` → `npm start`
> → 確認 `provider=postgres_pgvector`、log 無 `using JSON fallback`，即為成功。**全程不需改程式碼。**
