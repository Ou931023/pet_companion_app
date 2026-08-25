const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const serverJs = fs.readFileSync(path.join(__dirname, "..", "server.js"), "utf8");

function endpointSource() {
  const start = serverJs.indexOf("function normalizeCaregiverWebApiBaseUrl");
  const end = serverJs.indexOf('app.get("/api/agent/tools"', start);
  assert.ok(start >= 0 && end > start, "should find caregiver web config source");
  return serverJs.slice(start, end);
}

test("caregiver web config endpoint exposes only public Firebase Web config shape", () => {
  assert.ok(
    serverJs.includes('app.get("/api/caregiver-web/config"'),
    "server should expose a public caregiver web config endpoint"
  );
  for (const name of [
    "CAREGIVER_WEB_FIREBASE_API_KEY",
    "CAREGIVER_WEB_FIREBASE_AUTH_DOMAIN",
    "CAREGIVER_WEB_FIREBASE_PROJECT_ID",
    "CAREGIVER_WEB_FIREBASE_APP_ID",
  ]) {
    assert.ok(serverJs.includes(name), `server should read ${name}`);
  }
  assert.ok(
    serverJs.includes("caregiver_web_config_missing") &&
      serverJs.includes("Cache-Control") &&
      serverJs.includes("no-store"),
    "endpoint should fail clearly when config is missing and avoid caching"
  );
  const src = endpointSource();
  assert.ok(
    !src.includes("private_key") &&
      !src.includes("ADMIN_API_TOKEN") &&
      !src.includes("client_email"),
    "endpoint must not expose Firebase Admin service account or admin token fields"
  );
});

test("caregiver web config rejects stale API hosts and can infer current Render host", () => {
  const src = endpointSource();
  for (const host of [
    "ai-companion-api.onrender.com",
    "ai-companion-api-rdjv.onrender.com",
    "ai-companion-app-7mb8.onrender.com",
  ]) {
    assert.ok(src.includes(host), `endpoint should explicitly reject stale host ${host}`);
  }
  assert.ok(
    src.includes("normalizeCaregiverWebApiBaseUrl") &&
      src.includes("inferCaregiverWebApiBaseUrl") &&
      src.includes('req.get("x-forwarded-host")') &&
      src.includes('req.get("host")'),
    "endpoint should normalize configured URLs and infer the current deployed host"
  );
  assert.ok(
    src.includes("https://ai-companion-api-1gm7.onrender.com/api"),
    "endpoint should keep the current production backend as final fallback"
  );
});
