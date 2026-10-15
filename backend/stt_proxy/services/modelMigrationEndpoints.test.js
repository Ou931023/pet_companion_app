"use strict";
const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");
process.env.NODE_ENV = process.env.APP_ENV = "test";
process.env.OPENAI_API_KEY = "synthetic-placeholder";
process.env.PGVECTOR_ENABLED = "false";
for (const key of ["DATABASE_URL", "TELEGRAM_BOT_TOKEN", "MEMORY_MODEL", "CONVERSATION_TITLE_MODEL", "REALTIME_MODEL", "LEGACY_REALTIME_MODEL"]) delete process.env[key];
let choice = { finish_reason: "stop", message: { content: "synthetic response" } };
let request;
const load = Module._load;
Module._load = function(name, parent, ...rest) {
  if (name === "openai") return class {
    constructor() { this.chat = { completions: { create: async body => { request = body; return { choices: [choice] }; } } }; }
  };
  if (name === "./services/memory/memoryContextService") return {
    buildMemoryContext: async () => ({ memories: [{ id: "synthetic", memorySummary: "synthetic source" }], usedMemoryIds: ["synthetic"], memoryContext: "synthetic context" }),
    buildMemoryGreeting: async () => { throw new Error("Unexpected path"); },
  };
  return load.call(this, name, parent, ...rest);
};
const app = require("../server");
Module._load = load;
const { installResidentCallerStub } = require("./auth/residentCallerContext.testsupport");
const restore = installResidentCallerStub({ "synthetic-resident": { uid: "synthetic", userId: "synthetic", elderId: "11111111-1111-1111-1111-111111111111" } });
const originalFetch = global.fetch;
let upstream;
let upstreamStatus = 200;
global.fetch = async (url, init) => {
  if (String(url).startsWith("http://127.0.0.1:")) return originalFetch(url, init);
  assert.ok(["https://api.openai.com/v1/realtime/calls", "https://api.openai.com/v1/realtime/sessions"].includes(url), "No external request is permitted");
  upstream = String(url).endsWith("/calls") ? JSON.parse(init.body.get("session")) : JSON.parse(init.body);
  if (upstreamStatus !== 200) return new Response('{"error":{"message":"synthetic upstream failure"}}', { status: upstreamStatus });
  return new Response(String(url).endsWith("/calls") ? "v=0\r\nsynthetic answer" : JSON.stringify({ id: "synthetic-session", model: upstream.model, client_secret: { value: "synthetic-only" } }));
};
after(() => { restore(); global.fetch = originalFetch; });

async function serve(run) {
  const server = await new Promise(resolve => { const value = app.listen(0, "127.0.0.1", () => resolve(value)); });
  try { await run(`http://127.0.0.1:${server.address().port}`); }
  finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
}
async function post(base, route, body) {
  return fetch(base + route, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
}

test("title/greeting use Luna caps and refuse incomplete content through existing fallbacks", async () => serve(async base => {
  for (const mode of ["stop", "length", "content_filter", "refusal"]) {
    choice = { finish_reason: mode === "refusal" ? "stop" : mode, message: { content: "MODEL_ONLY", refusal: mode === "refusal" ? "synthetic refusal" : null } };
    const title = await (await post(base, "/api/conversation/title", { firstUserText: "synthetic input" })).json();
    assert.equal(request.model, "gpt-6-luna");
    assert.equal(request.max_completion_tokens, 128);
    assert.equal(title.title, mode === "stop" ? "MODEL_ONLY" : "synthetic inpu");
    const greeting = await (await fetch(base + "/api/memory/greeting", { headers: { Authorization: "Bearer synthetic-resident" } })).json();
    assert.equal(request.max_completion_tokens, 256);
    if (mode === "stop") assert.equal(greeting.greeting, "MODEL_ONLY");
    else {
      assert.notEqual(greeting.greeting, "MODEL_ONLY");
      assert.deepEqual(greeting.usedMemoryIds, []);
    }
  }
}));

test("GA WebRTC keeps SDP/VAD/transcription contracts; beta and rollback stay isolated", async () => serve(async base => {
  const call = () => fetch(base + "/api/realtime/call", { method: "POST", headers: { "Content-Type": "application/sdp" }, body: "v=0\r\nsynthetic offer" });
  const response = await call();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /application\/sdp/);
  assert.equal(await response.text(), "v=0\r\nsynthetic answer");
  assert.equal(upstream.model, "gpt-realtime-2.1");
  assert.deepEqual(upstream.reasoning, { effort: "low" });
  assert.equal(upstream.max_output_tokens, 1024);
  assert.deepEqual(upstream.audio.input.transcription, { model: "gpt-4o-transcribe", language: "zh" });
  assert.deepEqual(upstream.audio.input.turn_detection, { type: "server_vad", threshold: 0.55, prefix_padding_ms: 300, silence_duration_ms: 1500, create_response: true });
  process.env.REALTIME_MODEL = "gpt-realtime";
  await call();
  assert.equal(upstream.model, "gpt-realtime");
  assert.equal(upstream.reasoning, undefined);
  assert.equal(upstream.max_output_tokens, undefined);
  process.env.REALTIME_MODEL = "gpt-realtime-2.1";
  await post(base, "/api/realtime/session", {});
  assert.equal(upstream.model, "gpt-realtime");
  assert.equal(upstream.input_audio_transcription.model, "gpt-4o-mini-transcribe");
  assert.equal(upstream.reasoning, undefined);
  process.env.LEGACY_REALTIME_MODEL = "legacy-operator-override";
  await post(base, "/api/realtime/session", {});
  assert.equal(upstream.model, "legacy-operator-override");
  upstreamStatus = 400;
  const failed = await call();
  assert.equal(failed.status, 502);
  assert.equal((await failed.json()).code, "sdp_exchange_failed");
  upstreamStatus = 200;
  delete process.env.REALTIME_MODEL;
  delete process.env.LEGACY_REALTIME_MODEL;
}));
