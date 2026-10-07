"use strict";

const assert = require("node:assert/strict");
const { test, after } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const http = require("node:http");
const express = require("express");
const multer = require("multer");
const { multipartLimits, STT_MAX_BYTES, uploadDirectory } = require("./uploadPolicy");
const { createSttUploadHandler } = require("./sttUploadHandler");

// All data and providers are synthetic; dotenv is disabled before loading server.
process.env.APP_ENV = "test";
process.env.NODE_ENV = "test";
process.env.OPENAI_API_KEY = "test-placeholder";
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;
const root = fs.mkdtempSync(path.join(os.tmpdir(), "upload-security-"));
process.env.DAILY_CARE_TASKS_DATA_FILE = path.join(root, "tasks.json");
process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE = path.join(root, "submissions.json");
after(() => {
  fs.rmSync(root, { recursive: true, force: true });
  for (const name of ["pet_companion_stt", "pet_companion_daily_care_proofs", "pet_companion_taigi_asr"]) {
    fs.rmSync(uploadDirectory(name), { recursive: true, force: true });
  }
});

const deadline = { timeout: 10000 };
async function serve(app, run) {
  const server = await new Promise((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try { return await run(`http://127.0.0.1:${server.address().port}`); }
  finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}
function multipart(entries, close = true) {
  const boundary = "synthetic-upload-boundary";
  const chunks = [];
  for (const entry of entries) {
    const file = entry.file !== undefined;
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${entry.name}"${file ? `; filename="${entry.file}"` : ""}\r\n${file ? `Content-Type: ${entry.type || "application/octet-stream"}\r\n` : ""}\r\n`));
    chunks.push(Buffer.isBuffer(entry.value) ? entry.value : Buffer.from(entry.value || "audio"));
    chunks.push(Buffer.from("\r\n"));
  }
  if (close) chunks.push(Buffer.from(`--${boundary}--\r\n`));
  return { body: Buffer.concat(chunks), headers: { "Content-Type": `multipart/form-data; boundary=${boundary}` } };
}
async function post(url, entries, close = true, headers = {}) {
  const body = multipart(entries, close);
  return fetch(url, { method: "POST", ...body, headers: { ...body.headers, ...headers }, signal: AbortSignal.timeout(5000) });
}
async function eventuallyEmpty(dir) {
  for (let i = 0; i < 100; i++) {
    if (!fs.existsSync(dir) || fs.readdirSync(dir).length === 0) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.deepEqual(fs.readdirSync(dir), [], "upload files must be removed");
}
function harness({ configured = true, provider = async () => ({ text: " synthetic reply " }), limits = {} } = {}) {
  const dir = fs.mkdtempSync(path.join(root, "case-"));
  const app = express();
  const parse = multer({ dest: dir, limits: { ...multipartLimits(64), ...limits } }).single("audio");
  const handler = createSttUploadHandler({
    isConfigured: () => configured,
    client: { audio: { transcriptions: { create: provider } } },
  });
  app.post("/upload", (req, res) => parse(req, res, (error) => {
    if (error) return res.status(400).json({ code: error.code || "MALFORMED" });
    return handler(req, res);
  }));
  return { dir, app };
}
const audio = { name: "audio", file: "sample.m4a", value: "synthetic audio" };

for (const [name, entries, code] of [
  ["file bytes", [{ ...audio, value: Buffer.alloc(65) }], "LIMIT_FILE_SIZE"],
  ["files", [audio, audio], "LIMIT_FILE_COUNT"],
  ["fields", Array.from({ length: 9 }, (_, i) => ({ name: `f${i}` })), "LIMIT_FIELD_COUNT"],
  ["field name", [{ name: "n".repeat(101) }], "LIMIT_FIELD_KEY"],
  ["file field name", [{ ...audio, name: "n".repeat(101) }], "LIMIT_FIELD_KEY"],
  // Busboy marks a value truncated as soon as its buffer reaches fieldSize.
  ["field value at truncation boundary", [{ name: "note", value: "v".repeat(4096) }], "LIMIT_FIELD_VALUE"],
  ["field value", [{ name: "note", value: "v".repeat(4097) }], "LIMIT_FIELD_VALUE"],
  ["nesting", [audio, { name: "note[a][b][c]" }], "LIMIT_FIELD_NESTING"],
  ["array index", [audio, { name: "note[21]" }], "LIMIT_FIELD_ARRAY_INDEX"],
  ["unexpected file", [{ ...audio, name: "other" }], "LIMIT_UNEXPECTED_FILE"],
]) {
  test(`multipart rejects excessive ${name} and cleans files`, deadline, async () => {
    const { app, dir } = harness();
    await serve(app, async (url) => {
      const response = await post(`${url}/upload`, entries);
      assert.equal(response.status, 400);
      assert.equal((await response.json()).code, code);
      await eventuallyEmpty(dir);
    });
  });
}

test("multipart part count is independently bounded", deadline, async () => {
  assert.equal(multipartLimits(64).parts, 9);
  const { app, dir } = harness({ limits: { parts: 2 } });
  await serve(app, async (url) => {
    const response = await post(`${url}/upload`, [audio, { name: "one" }, { name: "two" }]);
    assert.equal(response.status, 400);
    assert.equal((await response.json()).code, "LIMIT_PART_COUNT");
    await eventuallyEmpty(dir);
  });
});

test("multipart accepts bounded nested fields and index at boundary", deadline, async () => {
  const { app, dir } = harness();
  await serve(app, async (url) => {
    const response = await post(`${url}/upload`, [audio, { name: "note[a][b]" }, { name: "tags[20]" }]);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).text, "synthetic reply");
    await eventuallyEmpty(dir);
  });
});

test("multipart accepts maximum file bytes, fields and part count with bounded value", deadline, async () => {
  const { app, dir } = harness();
  await serve(app, async (url) => {
    const entries = [{ ...audio, value: Buffer.alloc(64) }, ...Array.from({ length: 8 }, (_, i) => ({
      name: i ? `f${i}` : "n".repeat(100), value: i ? "ok" : "v".repeat(4095),
    }))];
    const response = await post(`${url}/upload`, entries);
    const body = await response.text();
    assert.equal(response.status, 200, body);
    await eventuallyEmpty(dir);
  });
});

for (const [name, options, entries, status, expected] of [
  ["missing key", { configured: false }, [audio], 500, "missing_api_key"],
  ["missing file", {}, [], 400, "audio file is required"],
  ["empty transcript", { provider: async () => ({ text: "  " }) }, [audio], 422, "Empty transcript"],
  ["zero-byte audio empty transcript", { provider: async () => ({ text: "" }) }, [{ ...audio, value: Buffer.alloc(0) }], 422, "Empty transcript"],
  ["provider failure", { provider: async () => { throw new Error("synthetic private provider failure"); } }, [audio], 500, "STT failed"],
  ["success", {}, [audio], 200, "synthetic reply"],
]) {
  test(`STT ${name} has bounded response and temp cleanup`, deadline, async () => {
    const { app, dir } = harness(options);
    await serve(app, async (url) => {
      const response = await post(`${url}/upload`, entries);
      assert.equal(response.status, status);
      const body = await response.json();
      assert.equal(body.code || body.text || body.message, expected);
      assert.equal(JSON.stringify(body).includes("private provider"), false);
      await eventuallyEmpty(dir);
    });
  });
}

test("truncated multipart returns within deadline and removes partial file", deadline, async () => {
  const { app, dir } = harness();
  await serve(app, async (url) => {
    const response = await post(`${url}/upload`, [audio], false);
    assert.equal(response.status, 400);
    await response.text();
    await eventuallyEmpty(dir);
  });
});

test("multipart without boundary fails promptly without temp files", deadline, async () => {
  const { app, dir } = harness();
  await serve(app, async (url) => {
    const response = await fetch(`${url}/upload`, {
      method: "POST", headers: { "Content-Type": "multipart/form-data" },
      body: "synthetic malformed body", signal: AbortSignal.timeout(5000),
    });
    assert.equal(response.status, 400);
    await response.text();
    await eventuallyEmpty(dir);
  });
});

test("client disconnect cancels synthetic provider and cleans audio stream/file", deadline, async () => {
  let started;
  const ready = new Promise((resolve) => { started = resolve; });
  let aborted;
  const cancelled = new Promise((resolve) => { aborted = resolve; });
  const { app, dir } = harness({ provider: async (_body, { signal }) => {
    started();
    return new Promise((_resolve, reject) => signal.addEventListener("abort", () => {
      aborted(); reject(new Error("synthetic abort"));
    }, { once: true }));
  } });
  await serve(app, async (url) => {
    const payload = multipart([audio]);
    const request = http.request(`${url}/upload`, { method: "POST", headers: payload.headers });
    request.on("error", () => {});
    request.end(payload.body);
    await ready;
    request.destroy();
    await cancelled;
    await eventuallyEmpty(dir);
  });
});

test("disconnect during partial upload removes parser-owned temp file", deadline, async () => {
  const { app, dir } = harness();
  await serve(app, async (url) => {
    const payload = multipart([{ ...audio, value: "partial" }], false);
    const request = http.request(`${url}/upload`, { method: "POST", headers: payload.headers });
    request.on("error", () => {});
    request.write(payload.body);
    for (let i = 0; i < 100 && fs.readdirSync(dir).length === 0; i++) await new Promise((resolve) => setTimeout(resolve, 10));
    assert.equal(fs.readdirSync(dir).length, 1);
    request.destroy();
    await eventuallyEmpty(dir);
  });
});

test("actual server STT wiring rejects malformed upload and cleans missing-key upload", deadline, async () => {
  const app = require("../server");
  const original = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = "";
  const dir = uploadDirectory("pet_companion_stt");
  try {
    await serve(app, async (url) => {
      const missingKey = await post(`${url}/api/stt/transcribe`, [audio]);
      assert.equal(missingKey.status, 500);
      assert.equal((await missingKey.json()).code, "missing_api_key");
      const rejected = await post(`${url}/api/stt/transcribe`, [audio, { name: "note[a][b][c]" }]);
      assert.equal(rejected.status, 400);
      assert.equal((await rejected.json()).code, "invalid_audio");
      const bounded = await post(`${url}/api/stt/transcribe`, [{ ...audio, value: Buffer.alloc(STT_MAX_BYTES) }]);
      assert.equal(bounded.status, 500, "25 MB audio reaches handler rather than parser rejection");
      assert.equal((await bounded.json()).code, "missing_api_key");
      const oversized = await post(`${url}/api/stt/transcribe`, [{ ...audio, value: Buffer.alloc(STT_MAX_BYTES + 1) }]);
      assert.equal(oversized.status, 400);
      assert.equal((await oversized.json()).code, "invalid_audio");
      await eventuallyEmpty(dir);
    });
  } finally { process.env.OPENAI_API_KEY = original; }
});

test("actual server taigi parser preserves octet-stream and enforces upload contract", deadline, async () => {
  const app = require("../server");
  const dir = uploadDirectory("pet_companion_taigi_asr");
  process.env.TAIGI_ASR_ENABLED = "true";
  process.env.TAIGI_ASR_PROVIDER = "test";
  process.env.TAIGI_ASR_TEST_TRANSCRIPT = "合成測試";
  try {
    await serve(app, async (url) => {
      const accepted = await post(`${url}/api/asr/taigi`, [audio]);
      assert.equal(accepted.status, 200);
      assert.equal((await accepted.json()).transcript, "合成測試");
      const invalid = await post(`${url}/api/asr/taigi`, [{ ...audio, file: "note.txt", type: "text/plain" }]);
      assert.equal(invalid.status, 400);
      assert.equal((await invalid.json()).error, "TAIGI_ASR_INVALID_AUDIO");
      const nested = await post(`${url}/api/asr/taigi`, [audio, { name: "note[21]" }]);
      assert.equal(nested.status, 400);
      assert.equal((await nested.json()).error, "LIMIT_FIELD_ARRAY_INDEX");
      const oversized = await post(`${url}/api/asr/taigi`, [{ ...audio, value: Buffer.alloc(10 * 1024 * 1024 + 1) }]);
      assert.equal(oversized.status, 400);
      assert.equal((await oversized.json()).error, "TAIGI_ASR_FILE_TOO_LARGE");
      await eventuallyEmpty(dir);
    });
  } finally {
    delete process.env.TAIGI_ASR_ENABLED;
    delete process.env.TAIGI_ASR_PROVIDER;
    delete process.env.TAIGI_ASR_TEST_TRANSCRIPT;
  }
});

test("STT upload limit remains the provider's 25 MB contract", () => {
  assert.equal(STT_MAX_BYTES, 25_000_000);
});

test("actual daily-care upload authenticates before parsing; ownership/errors clean and fallback keeps proof", deadline, async () => {
  const app = require("../server");
  const auth = require("./auth/residentCallerContext");
  const store = require("./dailyCareTask/dailyCareTaskStore");
  auth.setFirebaseAdminForTest({ isConfigured: () => true, verifyIdToken: async (token) => ({ uid: token }) });
  auth.setPgForTest({ isPostgresAvailable: async () => true, query: async (_sql, params) => ({ rows: [
    { id: "synthetic-user", role: "resident", status: "active", elder_id: params[0] },
  ] }) });
  const task = await store.createTask({ elderId: "upload-owner", title: "合成喝水測試", type: "hydration" });
  const id = task.task?.id || task.id;
  assert.ok(id);
  const dir = uploadDirectory("pet_companion_daily_care_proofs");
  const photo = { name: "photo", file: "proof.jpg", value: Buffer.concat([
    Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from("unique-synthetic-upload-security-proof"),
  ]) };
  const headers = { Authorization: "Bearer upload-owner" };
  let proofPath;
  const originalKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = "";
  try {
    await serve(app, async (url) => {
      const route = `${url}/api/daily-care-tasks/${id}/submit`;
      const unauth = await post(route, [{ ...photo, value: Buffer.alloc(8 * 1024 * 1024 + 1) }]);
      assert.equal(unauth.status, 401, "auth takes precedence over oversize parser failure");
      await unauth.text();
      const oversized = await post(route, [{ ...photo, value: Buffer.alloc(8 * 1024 * 1024 + 1) }], true, headers);
      assert.equal(oversized.status, 400);
      assert.equal((await oversized.json()).error, "invalid_photo");
      const crossOwner = await post(route, [photo], true, { Authorization: "Bearer another-upload-owner" });
      assert.equal(crossOwner.status, 403);
      assert.equal((await crossOwner.json()).error, "forbidden");
      const unknown = await post(`${url}/api/daily-care-tasks/no-synthetic-task/submit`, [photo], true, headers);
      assert.equal(unknown.status, 404);
      await unknown.text();
      const invalid = await post(route, [{ ...photo, file: "proof.txt" }], true, headers);
      assert.equal(invalid.status, 400);
      assert.equal((await invalid.json()).error, "photo_required");
      const success = await post(route, [photo], true, headers);
      assert.equal(success.status, 200);
      const result = await success.json();
      assert.equal(result.success, true);
      assert.equal(result.submission.hasProofImage, true);
      assert.equal(result.submission.status, "needs_review");
      const submission = await store.getSubmissionById(result.submission.id);
      proofPath = submission.proofImagePath;
      assert.deepEqual(fs.readFileSync(proofPath), photo.value, "JSON fallback must preserve its durable proof");
      await eventuallyEmpty(dir);
    });
  } finally {
    process.env.OPENAI_API_KEY = originalKey;
    auth.setFirebaseAdminForTest(null);
    auth.setPgForTest(null);
    if (proofPath) fs.unlinkSync(proofPath);
  }
});
