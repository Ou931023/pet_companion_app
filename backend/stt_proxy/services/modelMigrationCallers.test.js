"use strict";

const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");
process.env.NODE_ENV = process.env.APP_ENV = "test";
process.env.OPENAI_API_KEY = process.env.TAVILY_API_KEY = "synthetic-placeholder";
for (const key of ["MEMORY_MODEL", "MEMORY_EXTRACT_MODEL", "SEARCH_SUMMARY_MODEL", "WEB_SEARCH_SUMMARY_MODEL", "DATABASE_URL"]) delete process.env[key];
let choice = { finish_reason: "stop", message: { content: "synthetic answer" } };
let request;
let inserted = [];
let embeddings = [];
let providerThrows = false;
const originalLoad = Module._load;
Module._load = function(name, parent, ...rest) {
  if (name === "openai") return class {
    constructor() { this.chat = { completions: { create: async body => {
      request = body;
      if (providerThrows) throw new Error("synthetic failure");
      return { choices: [choice] };
    } } }; }
  };
  if (name === "./embeddingService" && parent.filename.endsWith("services" + require("node:path").sep + "memoryExtractor.js")) {
    return { createEmbedding: async text => { embeddings.push(text); return [1, 0]; } };
  }
  if (name === "../repositories/memoryRepository") return {
    insertMemory: async row => { inserted.push(row); return { id: "synthetic", summary: row.summary }; },
    softDeleteRecentMemory: async () => { throw new Error("Deletion forbidden in migration test"); },
  };
  return originalLoad.call(this, name, parent, ...rest);
};
const { extractAndStoreMemory } = require("./memoryExtractor");
const { summarizeWithAi, fallbackSummary } = require("./search/summarizer");
const { searchAndSummarize } = require("./tavilySearchService");
Module._load = originalLoad;
const originalFetch = global.fetch;
global.fetch = async url => {
  assert.equal(url, "https://api.tavily.com/search");
  return new Response(JSON.stringify({ answer: "synthetic source", results: [{ title: "Fixture", url: "https://example.test/source", content: "synthetic source" }] }), { headers: { "Content-Type": "application/json" } });
};
after(() => { global.fetch = originalFetch; });
const searchInput = { query: "synthetic query", mode: "general", results: [{ title: "Fixture", url: "https://example.test/source", summary: "synthetic source" }] };

test("legacy memory and both search callers default to Luna with bounded outputs and retain sources", async () => {
  choice = { finish_reason: "stop", message: { content: JSON.stringify({ shouldRemember: true, memoryType: "profile", summary: "我喜歡散步", importance: 0.5, tags: [] }) } };
  const memory = await extractAndStoreMemory({ userText: "我喜歡散步", userId: "synthetic-user" });
  assert.equal(memory.shouldRemember, true);
  assert.equal(request.model, "gpt-6-luna");
  assert.equal(request.max_completion_tokens, 2048);
  assert.deepEqual(request.response_format, { type: "json_object" });
  assert.deepEqual(embeddings, ["我喜歡散步"]);
  choice = { finish_reason: "stop", message: { content: "synthetic answer" } };
  const result = await summarizeWithAi(searchInput);
  assert.equal(result.answer, "synthetic answer");
  assert.equal(result.sources[0].url, "https://example.test/source");
  assert.equal(request.max_completion_tokens, 768);
  const web = await searchAndSummarize("synthetic query");
  assert.equal(web.sources[0].url, "https://example.test/source");
  assert.equal(request.model, "gpt-6-luna");
  assert.equal(request.reasoning_effort, "none");
  assert.equal(request.max_completion_tokens, 768);
});

for (const mode of ["length", "content_filter", "refusal", "malformed", "throw"]) {
  test(`legacy memory/search retain safe failure behavior: ${mode}`, async () => {
    inserted = []; embeddings = [];
    providerThrows = mode === "throw";
    choice = { finish_reason: ["length", "content_filter"].includes(mode) ? mode : "stop", message: {
      content: mode === "malformed" ? "{broken" : JSON.stringify({ shouldRemember: true, summary: "NEVER_PERSIST_THIS" }),
      refusal: mode === "refusal" ? "synthetic refusal" : null,
    } };
    const result = await extractAndStoreMemory({ userText: "我喜歡散步" });
    assert.equal(result.shouldRemember, false);
    assert.deepEqual(inserted, []);
    assert.deepEqual(embeddings, []);
    if (mode !== "malformed") {
      assert.deepEqual(await summarizeWithAi(searchInput), fallbackSummary(searchInput));
      await assert.rejects(searchAndSummarize("synthetic query"));
    }
    providerThrows = false;
  });
}

test("search-specific legacy overrides take precedence over shared MEMORY_MODEL", async () => {
  choice = { finish_reason: "stop", message: { content: "synthetic" } };
  process.env.MEMORY_MODEL = "shared-legacy-model";
  process.env.SEARCH_SUMMARY_MODEL = "gpt-4o-mini";
  process.env.WEB_SEARCH_SUMMARY_MODEL = "gpt-4o-mini";
  try {
    await summarizeWithAi(searchInput);
    assert.equal(request.model, "gpt-4o-mini");
    assert.equal(request.reasoning_effort, undefined);
    assert.equal(request.max_completion_tokens, undefined);
    await searchAndSummarize("synthetic query");
    assert.equal(request.model, "gpt-4o-mini");
    assert.equal(request.reasoning_effort, undefined);
  } finally {
    for (const key of ["MEMORY_MODEL", "SEARCH_SUMMARY_MODEL", "WEB_SEARCH_SUMMARY_MODEL"]) delete process.env[key];
  }
});
