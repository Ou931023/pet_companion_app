"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

process.env.NODE_ENV = "test";
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;

const app = require("../server");

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

test("production 不公開 crawler refresh 建置端點", async () => {
  const originalAppEnv = process.env.APP_ENV;
  const originalNodeEnv = process.env.NODE_ENV;
  const server = await startServer();
  try {
    process.env.APP_ENV = "production";
    process.env.NODE_ENV = "production";
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/crawl/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ urls: ["https://example.com"] }),
    });
    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), {
      success: false,
      error: "not_found",
    });
  } finally {
    server.close();
    if (originalAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = originalAppEnv;
    if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalNodeEnv;
  }
});
