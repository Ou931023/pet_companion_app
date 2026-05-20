# STT + Realtime + Vector Memory Backend

Node.js + Express backend for:
- OpenAI Speech-to-Text proxy
- OpenAI Realtime call broker
- PostgreSQL + pgvector long-term memory

## 1) Environment

Copy `.env.example` to `.env` and set:

```env
OPENAI_API_KEY=
PORT=3001
HOST=127.0.0.1
REALTIME_MODEL=gpt-realtime
REALTIME_VOICE=alloy
DATABASE_URL=postgres://postgres:password@localhost:5432/love_companion
EMBEDDING_MODEL=text-embedding-3-small
MEMORY_TOP_K=5
```

If your project already has `.env`, add the new memory/database variables into that same file.

## 2) Start PostgreSQL + pgvector

```bash
docker compose up -d
```

`docker-compose.yml` uses:
- DB: `love_companion`
- User: `postgres`
- Password: `password`
- Port: `5432`
- Volume: `postgres_data`

## PostgreSQL + pgvector (local dev)

This project uses PostgreSQL with the `pgvector` extension to store embeddings.

Start a local database (from this folder):

```bash
# from repo root
docker compose -f backend/stt_proxy/docker-compose.yml up -d

# install node deps
cd backend/stt_proxy
npm install

# run DB migrations (reads DATABASE_URL)
npm run db:migrate

# start service
npm start
```

Notes:
- Don't put real `OPENAI_API_KEY` into repository files. Use `.env` (gitignored) or CI secrets.
- For a physical phone on the same Wi-Fi, set `HOST=0.0.0.0` and run Flutter with
  `--dart-define=BACKEND_BASE_URL=http://<your-computer-ip>:3001`.
- The migration script uses `DATABASE_URL` environment variable. By default the compose file exposes Postgres on localhost:5432.

### iPhone on-device backend access

When running the Flutter app on an iPhone, `127.0.0.1` means the phone itself,
not your Mac. Use the Mac's Wi-Fi LAN IP instead.

```bash
ipconfig getifaddr en0
```

Put the iPhone and Mac on the same Wi-Fi, then start the backend so it is
reachable from the LAN:

```env
HOST=0.0.0.0
PORT=3001
```

Before opening the app, confirm from iPhone Safari:

```text
http://<your-mac-lan-ip>:3001/api/asr/taigi/status
```

Run Flutter with the same base URL:

```bash
flutter run \
  --dart-define=BACKEND_BASE_URL=http://<your-mac-lan-ip>:3001
```

If you configure the backend URL from the app settings, use the full STT proxy
URL:

```text
http://<your-mac-lan-ip>:3001/api/stt/transcribe
```

## 3) Run migrations

```bash
npm install
npm run db:migrate
```

Expected final log:

```text
[DB] migrations completed
```

## 4) Start backend

```bash
npm start
```

## 5) APIs

- `GET /health`
- `POST /api/stt/transcribe`
- `POST /api/asr/taigi`
- `POST /api/realtime/session`
- `POST /api/realtime/call?petName=小白&userId=local_user`
- `POST /api/memory/extract`
- `POST /api/memory/search`
- `GET /api/memory/greeting?userId=local_user&petName=小白&localHour=14`
- `POST /api/memory/forget-recent`

### Taigi ASR Phase 2

`POST /api/asr/taigi` accepts short audio uploads as `multipart/form-data`
with field name `audio`. The backend normalizes audio to 16 kHz mono WAV
with `ffmpeg`, then calls the configured Taigi ASR provider. Phase 2 supports
short recording transcription only; it is not streaming ASR.

`GET /api/asr/taigi/status` checks whether Taigi ASR is enabled and whether the
basic runtime dependencies are available. Product UI should translate this into
friendly states such as "台語語音辨識可使用" or "台語語音辨識暫時無法使用";
do not show provider names, model IDs, raw JSON, or stack traces to users.

`POST /api/asr/taigi/warmup` runs the environment checks plus
`transcribe_taigi.py --dry-run`. It does not perform a real transcription and it
does not make the Python ASR model a persistent worker. It is intended for demo
preflight checks before using short recording ASR.

Enable it with:

```env
TAIGI_ASR_ENABLED=true
TAIGI_ASR_PROVIDER=python
TAIGI_ASR_MODEL=NUTN-KWS/Whisper-Taiwanese-model-v0.5
TAIGI_ASR_PYTHON=python3
```

Install system and Python dependencies on the backend host:

```bash
# system
ffmpeg

# python
pip install transformers torch torchaudio librosa soundfile
```

Dry-run can also be checked directly:

```bash
python3 scripts/transcribe_taigi.py \
  --dry-run \
  --model NUTN-KWS/Whisper-Taiwanese-model-v0.5
```

If the model, Python packages, or `ffmpeg` are missing, the endpoint returns a
clear JSON error such as `TAIGI_ASR_UNAVAILABLE`; the Flutter app shows a
friendly message and does not fall back to fake transcripts.

Operational notes:

- The first inference can be slow because the Python provider starts a
  subprocess and loads the ASR model for the request. After the model files are
  cached locally, later requests are usually faster, but Phase 2 does not keep a
  warm ASR worker alive.
- Phase 2.5 is still short recording ASR, not streaming ASR. Because the Python
  provider is not a persistent worker, a real transcription can still take
  around 20 seconds on local demo hardware.
- Run `/api/asr/taigi/warmup` before a demo to check the environment and model
  configuration. Warmup does not replace the cost of the later real
  transcription.
- `confidence` may be `0` when the underlying model or pipeline does not expose
  a reliable confidence score. Treat it as unavailable in product UI rather than
  as a low-confidence percentage.
- Test Taigi ASR with short, clearly recorded clips first. A 3 to 5 second audio
  file with close microphone distance and low background noise is recommended.
- Recognition quality can be affected by quiet recordings, very short clips,
  background noise, the `m4a` to 16 kHz mono WAV conversion step, and the model's
  coverage of the spoken sentence.
- In the Flutter app, recognized Taigi text is shown to the user first. The
  transcript is sent into the companion conversation only after the user confirms
  it.
- While transcription is running, the app shows "台語辨識中，請稍等" and blocks
  duplicate ASR requests for the same recording.

## 6) Test memory API quickly

```bash
curl -X POST http://localhost:3001/api/memory/extract ^
  -H "Content-Type: application/json" ^
  -d "{\"userId\":\"local_user\",\"sessionId\":\"session_1\",\"turnId\":\"turn_1\",\"userText\":\"我昨晚睡不好，今天很累\",\"aiReply\":\"辛苦你了，我陪你慢慢說。\",\"emotion\":\"tired\"}"
```

```bash
curl -X POST http://localhost:3001/api/memory/search ^
  -H "Content-Type: application/json" ^
  -d "{\"userId\":\"local_user\",\"query\":\"找出最近值得關心的使用者近況\",\"topK\":5}"
```

```bash
curl "http://localhost:3001/api/memory/greeting?userId=local_user&petName=小白&localHour=14"
```

## 7) Verify Realtime memory injection

When calling `/api/realtime/call`, backend logs:
- pet name
- user id
- injected memory count

Only memory summaries are injected (max `MEMORY_TOP_K`), not full original user text.

## 8) HNSW / IVFFLAT fallback

Migration first attempts HNSW index:
- `USING hnsw (embedding vector_cosine_ops)`

If pgvector build does not support HNSW, migration falls back to IVFFLAT:
- `USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)`

## 9) Common errors

- `extension "vector" does not exist`
  - Use pgvector image and run migrations after DB is healthy.
- `relation "memory_items" does not exist`
  - Run `npm run db:migrate`.
- `embedding dimension mismatch`
  - Ensure embeddings come from `text-embedding-3-small` (1536 dimensions).
- `DATABASE_URL missing`
  - Add `DATABASE_URL` to `.env`.
- `OPENAI_API_KEY missing`
  - Add valid OpenAI key to `.env`.
