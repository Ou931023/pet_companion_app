"use strict";
const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

process.env.NODE_ENV = "test";
process.env.APP_ENV = "test";
process.env.OPENAI_API_KEY = "synthetic-placeholder";
process.env.PGVECTOR_ENABLED = "false";
process.env.REALTIME_RATE_LIMIT_MAX = "100";
delete process.env.DATABASE_URL;
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;
const originals = [];
function stub(name, exports) {
  const id = require.resolve(name);
  originals.push([id, require.cache[id]]);
  require.cache[id] = { id, filename: id, loaded: true, exports };
}
stub("./memory/embeddingService", {
  createEmbedding: async () => ({ embedding: [1, 0, 0], provider: "synthetic" }),
});
const store = require("./memory/memoryStore");
let releaseRetrieval;
let retrievalGate;
let failAccounting = false;
let accountingTask;
let accountingGate;
let releaseAccounting;
let contextTasks = [];
stub("./memory/memoryStore", {
  ...store,
  searchMemoriesByEmbedding: async (...args) => {
    if (retrievalGate) await retrievalGate;
    return store.searchMemoriesByEmbedding(...args);
  },
  markMemoriesUsed: ids => {
    accountingTask = failAccounting
      ? Promise.reject(new Error("synthetic accounting failure"))
      : (async () => { if (accountingGate) await accountingGate; return store.markMemoriesUsed(ids); })();
    return accountingTask;
  },
});
const contextService = require("./memory/memoryContextService");
let contextDone;
stub("./memory/memoryContextService", {
  ...contextService,
  buildMemoryContext: args => {
    const task = contextService.buildMemoryContext(args).finally(() => contextDone?.());
    contextTasks.push(task);
    return task;
  },
});
const app = require("../server");
const realFetch = global.fetch;
after(() => {
  global.fetch = realFetch;
  for (const [id, original] of originals.reverse()) {
    if (original) require.cache[id] = original; else delete require.cache[id];
  }
});

const included = "合成人物喜歡在河邊散步";
const excluded = "合成人物不相關的舊記憶";
function memory(id, summary, embedding = [1, 0, 0]) {
  return { id, userId: "synthetic-injection-user", memoryText: summary,
    memorySummary: summary, memoryType: "preference", importance: 5,
    confidence: 1, embedding, isActive: true, useCount: 0,
    createdAt: new Date().toISOString() };
}

async function fixture(fn) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "realtime-injection-"));
  const previousDir = process.env.MEMORY_DATA_DIR;
  process.env.MEMORY_DATA_DIR = dir;
  retrievalGate = null; releaseRetrieval = null; failAccounting = false; accountingTask = null;
  accountingGate = null; releaseAccounting = null; contextTasks = [];
  const done = new Promise(resolve => { contextDone = resolve; });
  const memoriesFile = path.join(dir, "companion_memories.json");
  const eventsFile = path.join(dir, "memory_events.json");
  await fs.writeFile(memoriesFile, JSON.stringify([
    memory("synthetic-1", included), memory("synthetic-2", excluded, [0, 1, 0]),
    memory("synthetic-3", "完整記憶太長".repeat(130)),
  ]));
  await fs.writeFile(eventsFile, "[]");
  const submitted = [];
  let upstreamStatus = 200;
  let upstreamThrows = false;
  let bodyThrows = false;
  global.fetch = async (url, options) => {
    if (String(url).startsWith("http://127.0.0.1:")) return realFetch(url, options);
    assert.equal(String(url), "https://api.openai.com/v1/realtime/calls", "unexpected external call blocked");
    submitted.push(JSON.parse(options.body.get("session")));
    if (upstreamThrows) throw new Error("synthetic transport failure");
    if (bodyThrows) return { ok: true, status: 200, text: async () => { throw new Error("synthetic body failure"); } };
    return new Response(upstreamStatus === 200 ? "synthetic-answer-sdp" : "synthetic upstream failure", { status: upstreamStatus });
  };
  const server = await new Promise(resolve => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
  });
  try {
    await fn({ submitted, done, memoriesFile,
      delay: () => { retrievalGate = new Promise(resolve => { releaseRetrieval = resolve; }); },
      release: () => releaseRetrieval?.(),
      noDelay: () => { retrievalGate = null; },
      settleContexts: () => Promise.all(contextTasks),
      delayAccounting: () => { accountingGate = new Promise(resolve => { releaseAccounting = resolve; }); },
      releaseAccounting: () => releaseAccounting?.(),
      failUpstream: status => { upstreamStatus = status; },
      throwUpstream: () => { upstreamThrows = true; },
      failBody: () => { bodyThrows = true; },
      request: (userId = "synthetic-injection-user") => fetch(`http://127.0.0.1:${server.address().port}/api/realtime/call?userId=${userId}`, {
        method: "POST", headers: { "Content-Type": "application/sdp" }, body: "synthetic-offer-sdp",
      }),
      snapshot: async () => {
        await accountingTask?.catch(() => {});
        return { memories: JSON.parse(await fs.readFile(memoriesFile, "utf8")),
          events: JSON.parse(await fs.readFile(eventsFile, "utf8")) };
      },
    });
  } finally {
    releaseRetrieval?.();
    releaseAccounting?.();
    await Promise.allSettled(contextTasks);
    await accountingTask?.catch(() => {});
    global.fetch = realFetch;
    await new Promise(resolve => server.close(resolve));
    if (previousDir === undefined) delete process.env.MEMORY_DATA_DIR;
    else process.env.MEMORY_DATA_DIR = previousDir;
    assert.equal(path.dirname(dir), path.resolve(os.tmpdir()));
    await fs.rm(dir, { recursive: true, force: true });
  }
}

function assertUsage(snapshot, expectedIds) {
  assert.deepEqual(snapshot.events.filter(e => e.eventType === "used_in_prompt").map(e => e.memoryId).sort(), expectedIds);
  for (const m of snapshot.memories) assert.equal(m.useCount, expectedIds.includes(m.id) ? 1 : 0, m.id);
}

test("late retrieval after Realtime timeout never records omitted prompt memories", async () => fixture(async f => {
  f.delay();
  const response = await f.request();
  assert.equal(response.status, 200);
  assert.equal(f.submitted.length, 1);
  assert.ok(!f.submitted[0].instructions.includes(included));
  assert.ok(!f.submitted[0].instructions.includes(excluded));
  f.release();
  await f.done; // Check AFTER late context completion, not just the timeout response.
  assertUsage(await f.snapshot(), []);
}));

test("fast Realtime injection records only IDs whose full text reached upstream", async () => fixture(async f => {
  const response = await f.request();
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "synthetic-answer-sdp");
  assert.equal(f.submitted.length, 1);
  assert.ok(f.submitted[0].instructions.includes(included));
  assert.ok(!f.submitted[0].instructions.includes(excluded));
  assert.ok(!f.submitted[0].instructions.includes("完整記憶太長"));
  assertUsage(await f.snapshot(), ["synthetic-1"]);
}));

for (const failure of ["http", "transport", "body"]) {
  test(`failed upstream ${failure} does not record accepted injection`, async () => fixture(async f => {
    if (failure === "http") f.failUpstream(503);
    else if (failure === "body") f.failBody();
    else f.throwUpstream();
    const response = await f.request();
    assert.equal(response.status, failure === "http" ? 502 : 500);
    assert.ok(f.submitted[0].instructions.includes(included));
    assertUsage(await f.snapshot(), []);
  }));
}

test("empty retrieval sends no memory and records no injection", async () => fixture(async f => {
  await fs.writeFile(f.memoriesFile, "[]");
  assert.equal((await f.request()).status, 200);
  assert.ok(!f.submitted[0].instructions.includes(included));
  assertUsage(await f.snapshot(), []);
}));

test("accounting failure does not discard an accepted session or selected context", async () => fixture(async f => {
  failAccounting = true;
  assert.equal((await f.request()).status, 200);
  assert.ok(f.submitted[0].instructions.includes(included));
  assertUsage(await f.snapshot(), []);
}));

test("existing buildMemoryContext callers still record usage by default", async () => fixture(async f => {
  const result = await contextService.buildMemoryContext({ userId: "synthetic-injection-user", userText: "最近喜歡什麼活動", queryEmbedding: [1, 0, 0] });
  assert.deepEqual(result.usedMemoryIds, ["synthetic-1"]);
  assertUsage(await f.snapshot(), ["synthetic-1"]);
}));

test("explicit retrieval-only context leaves counters unchanged", async () => fixture(async f => {
  const result = await contextService.buildMemoryContext({ userId: "synthetic-injection-user", userText: "最近喜歡什麼活動", queryEmbedding: [1, 0, 0], recordUsage: false });
  assert.deepEqual(result.usedMemoryIds, ["synthetic-1"]);
  assert.ok(result.memoryContext.includes(included));
  assertUsage(await f.snapshot(), []);
}));

test("slow accounting does not block the accepted SDP response", async () => fixture(async f => {
  f.delayAccounting();
  let timer;
  try {
    const response = await Promise.race([f.request(), new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error("SDP blocked on accounting")), 1000);
    })]);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "synthetic-answer-sdp");
    f.releaseAccounting();
    assertUsage(await f.snapshot(), ["synthetic-1"]);
  } finally { clearTimeout(timer); }
}));

test("a late request never borrows a subsequent user's injected IDs", async () => fixture(async f => {
  const records = JSON.parse(await fs.readFile(f.memoriesFile, "utf8"));
  const otherText = "另一位合成人物喜歡園藝";
  records.push({ ...memory("synthetic-other", otherText), userId: "synthetic-other-user" });
  await fs.writeFile(f.memoriesFile, JSON.stringify(records));
  f.delay();
  assert.equal((await f.request()).status, 200);
  f.noDelay();
  assert.equal((await f.request("synthetic-other-user")).status, 200);
  assert.ok(!f.submitted[0].instructions.includes(included));
  assert.ok(!f.submitted[0].instructions.includes(otherText));
  assert.ok(f.submitted[1].instructions.includes(otherText));
  assert.ok(!f.submitted[1].instructions.includes(included));
  f.release();
  await f.settleContexts();
  assertUsage(await f.snapshot(), ["synthetic-other"]);
}));
