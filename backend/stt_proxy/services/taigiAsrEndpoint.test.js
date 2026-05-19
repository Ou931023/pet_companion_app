const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");

process.env.NODE_ENV = "test";
const app = require("../server");

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postAudio(baseUrl, { filename = "sample.wav", type = "audio/wav" } = {}) {
  const form = new FormData();
  form.append("audio", new Blob([Buffer.from("fake-audio")], { type }), filename);
  return fetch(`${baseUrl}/api/asr/taigi`, {
    method: "POST",
    body: form,
  });
}

function countRecentUploadFiles(startedAt) {
  const dir = path.join(os.tmpdir(), "pet_companion_taigi_asr");
  if (!fs.existsSync(dir)) return 0;
  return fs.readdirSync(dir).filter((name) => {
    const stat = fs.statSync(path.join(dir, name));
    return stat.mtimeMs >= startedAt - 1000;
  }).length;
}

test("POST /api/asr/taigi returns 400 without audio", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/asr/taigi`, { method: "POST" });
    const body = await response.json();

    assert.equal(response.status, 400);
    assert.equal(body.error, "TAIGI_ASR_AUDIO_REQUIRED");
  } finally {
    server.close();
  }
});

test("POST /api/asr/taigi returns unavailable when disabled", async () => {
  process.env.TAIGI_ASR_ENABLED = "false";
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await postAudio(baseUrl);
    const body = await response.json();

    assert.equal(response.status, 503);
    assert.equal(body.error, "TAIGI_ASR_UNAVAILABLE");
  } finally {
    server.close();
  }
});

test("POST /api/asr/taigi rejects non-audio uploads", async () => {
  process.env.TAIGI_ASR_ENABLED = "true";
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await postAudio(baseUrl, {
      filename: "note.txt",
      type: "text/plain",
    });
    const body = await response.json();

    assert.equal(response.status, 400);
    assert.equal(body.error, "TAIGI_ASR_INVALID_AUDIO");
  } finally {
    server.close();
  }
});

test("POST /api/asr/taigi returns transcript when provider succeeds", async () => {
  process.env.TAIGI_ASR_ENABLED = "true";
  process.env.TAIGI_ASR_PROVIDER = "test";
  process.env.TAIGI_ASR_TEST_TRANSCRIPT = "今仔日心情無好";
  process.env.TAIGI_ASR_TEST_CONFIDENCE = "0.82";
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await postAudio(baseUrl);
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.language, "taigi");
    assert.equal(body.transcript, "今仔日心情無好");
    assert.equal(body.confidence, 0.82);
    assert.equal(body.source, "taigi-asr");
    assert.equal(typeof body.durationMs, "number");
  } finally {
    server.close();
  }
});

test("POST /api/asr/taigi cleans uploaded temp file on error", async () => {
  process.env.TAIGI_ASR_ENABLED = "false";
  delete process.env.TAIGI_ASR_PROVIDER;
  const startedAt = Date.now();
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await postAudio(baseUrl);
    await response.text();
    await new Promise((resolve) => setTimeout(resolve, 80));

    assert.equal(response.status, 503);
    assert.equal(countRecentUploadFiles(startedAt), 0);
  } finally {
    server.close();
  }
});
