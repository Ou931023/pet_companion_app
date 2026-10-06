const assert = require("node:assert/strict");
const { test } = require("node:test");

const { resolveDeploymentRevision } = require("./deploymentRevision");

test("returns the exact normalized Render commit SHA", () => {
  assert.equal(
    resolveDeploymentRevision({
      RENDER_GIT_COMMIT: "E6C6169A46C52B48489062D680EE142E2E486F75",
    }),
    "e6c6169a46c52b48489062d680ee142e2e486f75",
  );
});

test("does not reflect malformed or secret-like values", () => {
  assert.equal(resolveDeploymentRevision({ RENDER_GIT_COMMIT: "main" }), null);
  assert.equal(
    resolveDeploymentRevision({ RENDER_GIT_COMMIT: "token=do-not-reflect" }),
    null,
  );
  assert.equal(resolveDeploymentRevision({}), null);
});

test("does not infer a revision from unrelated environment variables", () => {
  assert.equal(
    resolveDeploymentRevision({
      GITHUB_SHA: "a".repeat(40),
      DATABASE_URL: "postgres://private",
      OPENAI_API_KEY: "private",
    }),
    null,
  );
});
