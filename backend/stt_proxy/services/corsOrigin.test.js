// CR-0054 / CR-0064：CORS 來源解析與回應安全邊界測試。
//
// 目的：守住 server.js 的 CORS middleware 行為，避免回歸：
//   - owner 只設新名 CORS_ALLOWED_ORIGINS 時 middleware 仍讀 legacy ALLOWED_ORIGINS。
//   - production OPTIONS 仍回傳 http://localhost:5173 之類舊 dev origin（CR-0064）。
//   - 未授權 origin 被反射（allow-all）。
//
// 作法：不重載整個 server（其 CORS 設定於 module-load 時固定，且載入成本高）。
// 改以「最小 express 實例」原樣複製 server.js（CR-0064 後）的「單一手動 CORS
// middleware」——同一份白名單解析（config/env.resolveCorsOrigins）+ 同一段 origin
// 逐一比對 + 同樣的方法 / 表頭 / 204 行為——掛一條 GET /health，透過 node:http（fetch）
// 發帶/不帶 Origin 的 GET 與 OPTIONS 請求，斷言 access-control-* 表頭與狀態。
// 不新增重依賴、不改任何 API 契約。

const assert = require("node:assert/strict");
const { test } = require("node:test");

process.env.NODE_ENV = "test";

const express = require("express");
const { resolveCorsOrigins } = require("../config/env");

// 原樣複製 server.js（CR-0064 後）的單一 CORS middleware；以 env 物件參數化，
// 等價測試同一段判斷邏輯。
const CORS_ALLOW_METHODS = "GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS";
const CORS_ALLOW_HEADERS =
  "Content-Type, Authorization, X-Admin-Token, X-Requested-With";

function buildApp(env) {
  const app = express();
  const allowedOrigins = (resolveCorsOrigins(env) || "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);

  app.use((req, res, next) => {
    const origin = req.headers.origin;

    if (origin && allowedOrigins.includes(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
      res.setHeader("Access-Control-Allow-Credentials", "true");
      res.setHeader("Access-Control-Allow-Methods", CORS_ALLOW_METHODS);
      res.setHeader("Access-Control-Allow-Headers", CORS_ALLOW_HEADERS);
    }

    if (req.method === "OPTIONS") {
      return res.sendStatus(204);
    }

    return next();
  });
  app.get("/health", (_, res) => res.json({ ok: true }));
  return app;
}

function startServer(app) {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () =>
      resolve({ server, port: server.address().port }),
    );
  });
}

async function request(env, { method = "GET", headers } = {}) {
  const { server, port } = await startServer(buildApp(env));
  try {
    const res = await fetch(`http://127.0.0.1:${port}/health`, {
      method,
      headers,
    });
    // 讀完 body 避免 socket 懸置。
    await res.text();
    return res;
  } finally {
    await new Promise((r) => server.close(r));
  }
}

test("CORS_ALLOWED_ORIGINS 設定：列入的 origin 放行、未列入的被擋", async () => {
  const env = { CORS_ALLOWED_ORIGINS: "https://app.example.com" };

  const allowed = await request(env, {
    headers: { Origin: "https://app.example.com" },
  });
  assert.equal(allowed.status, 200);
  assert.equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://app.example.com",
  );
  assert.equal(allowed.headers.get("access-control-allow-credentials"), "true");

  const blocked = await request(env, {
    headers: { Origin: "https://evil.example.com" },
  });
  // 未授權 origin 不回 access-control-allow-origin 表頭。
  assert.equal(blocked.headers.get("access-control-allow-origin"), null);
});

test("只設 legacy ALLOWED_ORIGINS（不設新名）仍生效（向後相容）", async () => {
  const env = { ALLOWED_ORIGINS: "https://legacy.example.com" };

  const allowed = await request(env, {
    headers: { Origin: "https://legacy.example.com" },
  });
  assert.equal(allowed.status, 200);
  assert.equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://legacy.example.com",
  );

  const blocked = await request(env, {
    headers: { Origin: "https://other.example.com" },
  });
  assert.equal(blocked.headers.get("access-control-allow-origin"), null);
});

test("兩者都設時 CORS_ALLOWED_ORIGINS 優先", async () => {
  const env = {
    CORS_ALLOWED_ORIGINS: "https://new.example.com",
    ALLOWED_ORIGINS: "https://legacy.example.com",
  };

  const newAllowed = await request(env, {
    headers: { Origin: "https://new.example.com" },
  });
  assert.equal(
    newAllowed.headers.get("access-control-allow-origin"),
    "https://new.example.com",
  );

  // legacy 值在新名存在時不應再被採用 → legacy origin 被擋。
  const legacyBlocked = await request(env, {
    headers: { Origin: "https://legacy.example.com" },
  });
  assert.equal(legacyBlocked.headers.get("access-control-allow-origin"), null);
});

test("空清單（未設任何白名單）：fail-closed，不反射任意 origin（不 allow-all）", async () => {
  const env = {}; // 兩個變數都未設 → 空清單

  const res = await request(env, {
    headers: { Origin: "https://anything.example.com" },
  });
  // 請求本身放行（200），但不可回 allow-origin 表頭（CR-0064：fail closed）。
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("access-control-allow-origin"), null);
});

test("無 Origin header（curl / Flutter 原生 HTTP / health check）一律放行", async () => {
  // 有設白名單時，仍須放行不帶 Origin 的請求。
  const withList = await request(
    { CORS_ALLOWED_ORIGINS: "https://app.example.com" },
    {},
  );
  assert.equal(withList.status, 200);

  // 空清單時亦放行不帶 Origin 的請求。
  const emptyList = await request({}, {});
  assert.equal(emptyList.status, 200);
});

// CR-0064：production Render caregiver_web 場景回歸守門。
test("production caregiver_web origin 放行，且絕不回 localhost:5173", async () => {
  const env = {
    CORS_ALLOWED_ORIGINS: "https://ai-companion-caregiver-web.onrender.com",
  };

  const res = await request(env, {
    headers: { Origin: "https://ai-companion-caregiver-web.onrender.com" },
  });
  assert.equal(
    res.headers.get("access-control-allow-origin"),
    "https://ai-companion-caregiver-web.onrender.com",
  );
  assert.equal(res.headers.get("access-control-allow-credentials"), "true");
  // 絕不可再回傳舊 dev origin。
  assert.notEqual(
    res.headers.get("access-control-allow-origin"),
    "http://localhost:5173",
  );

  // 舊 dev origin 本身應被擋。
  const devOrigin = await request(env, {
    headers: { Origin: "http://localhost:5173" },
  });
  assert.equal(devOrigin.headers.get("access-control-allow-origin"), null);
});

test("OPTIONS preflight：授權 origin 回 204 + 完整方法/表頭/credentials", async () => {
  const env = {
    CORS_ALLOWED_ORIGINS: "https://ai-companion-caregiver-web.onrender.com",
  };

  const res = await request(env, {
    method: "OPTIONS",
    headers: {
      Origin: "https://ai-companion-caregiver-web.onrender.com",
      "Access-Control-Request-Method": "GET",
    },
  });
  assert.equal(res.status, 204);
  assert.equal(
    res.headers.get("access-control-allow-origin"),
    "https://ai-companion-caregiver-web.onrender.com",
  );
  assert.equal(res.headers.get("access-control-allow-credentials"), "true");

  const methods = res.headers.get("access-control-allow-methods") || "";
  for (const m of ["GET", "HEAD", "PUT", "PATCH", "POST", "DELETE", "OPTIONS"]) {
    assert.ok(methods.includes(m), `methods 應包含 ${m}，實得：${methods}`);
  }

  const allowHeaders = res.headers.get("access-control-allow-headers") || "";
  for (const h of [
    "Content-Type",
    "Authorization",
    "X-Admin-Token",
    "X-Requested-With",
  ]) {
    assert.ok(allowHeaders.includes(h), `headers 應包含 ${h}，實得：${allowHeaders}`);
  }
});

test("OPTIONS preflight：未授權 origin 回 204 但不帶 allow-origin（fail closed）", async () => {
  const env = {
    CORS_ALLOWED_ORIGINS: "https://ai-companion-caregiver-web.onrender.com",
  };

  const res = await request(env, {
    method: "OPTIONS",
    headers: {
      Origin: "http://localhost:5173",
      "Access-Control-Request-Method": "GET",
    },
  });
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("access-control-allow-origin"), null);
});
