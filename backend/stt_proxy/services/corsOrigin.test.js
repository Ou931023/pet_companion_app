// CR-0054 Batch 1：CORS 來源解析安全邊界測試。
//
// 目的：守住 server.js 的 CORS middleware 來源解析行為，避免「owner 只設新名
// CORS_ALLOWED_ORIGINS 時 middleware 仍讀 legacy ALLOWED_ORIGINS → production allow-all」回歸。
//
// 作法：不重載整個 server（其 CORS 設定於 module-load 時固定，且載入成本高）。
// 改以「最小 express 實例」原樣複製 server.js 的 CORS 接線——使用真實 cors 套件 +
// 真實 config/env.resolveCorsOrigins + 與 server.js 一字不差的 split / origin 判斷邏輯——
// 掛一條 GET /health，透過 node:http（fetch）發帶/不帶 Origin 的請求，斷言
// access-control-allow-origin 表頭與狀態。不新增重依賴、不改任何 API 契約。

const assert = require("node:assert/strict");
const { test } = require("node:test");

process.env.NODE_ENV = "test";

const express = require("express");
const cors = require("cors");
const { resolveCorsOrigins } = require("../config/env");

// 原樣複製 server.js（CR-0054 後）CORS 接線：
//   const allowedOriginsEnv = (resolveCorsOrigins(process.env) || '').trim();
//   const allowedOrigins = allowedOriginsEnv ? allowedOriginsEnv.split(',').map(s => s.trim()) : [];
//   app.use(cors({ origin: function(origin, callback) { ... } }));
// 此處以 env 物件參數化，等價測試同一段判斷邏輯。
function buildApp(env) {
  const app = express();
  const allowedOriginsEnv = (resolveCorsOrigins(env) || "").trim();
  const allowedOrigins = allowedOriginsEnv
    ? allowedOriginsEnv.split(",").map((s) => s.trim())
    : [];
  app.use(
    cors({
      origin: function (origin, callback) {
        if (!origin && allowedOrigins.length === 0) return callback(null, true); // allow non-browser (curl, server)
        if (!origin) return callback(null, true);
        if (allowedOrigins.length === 0 || allowedOrigins.indexOf(origin) !== -1) {
          return callback(null, true);
        }
        return callback(new Error("CORS not allowed"));
      },
    }),
  );
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

async function getHealth(env, headers) {
  const { server, port } = await startServer(buildApp(env));
  try {
    const res = await fetch(`http://127.0.0.1:${port}/health`, { headers });
    // 讀完 body 避免 socket 懸置。
    await res.text();
    return res;
  } finally {
    await new Promise((r) => server.close(r));
  }
}

test("CORS_ALLOWED_ORIGINS 設定：列入的 origin 放行、未列入的被擋", async () => {
  const env = { CORS_ALLOWED_ORIGINS: "https://app.example.com" };

  const allowed = await getHealth(env, { Origin: "https://app.example.com" });
  assert.equal(allowed.status, 200);
  assert.equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://app.example.com",
  );

  const blocked = await getHealth(env, { Origin: "https://evil.example.com" });
  // cors 在來源不被允許時不會回傳 access-control-allow-origin 表頭。
  assert.equal(blocked.headers.get("access-control-allow-origin"), null);
});

test("只設 legacy ALLOWED_ORIGINS（不設新名）仍生效（向後相容）", async () => {
  const env = { ALLOWED_ORIGINS: "https://legacy.example.com" };

  const allowed = await getHealth(env, { Origin: "https://legacy.example.com" });
  assert.equal(allowed.status, 200);
  assert.equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://legacy.example.com",
  );

  const blocked = await getHealth(env, { Origin: "https://other.example.com" });
  assert.equal(blocked.headers.get("access-control-allow-origin"), null);
});

test("兩者都設時 CORS_ALLOWED_ORIGINS 優先", async () => {
  const env = {
    CORS_ALLOWED_ORIGINS: "https://new.example.com",
    ALLOWED_ORIGINS: "https://legacy.example.com",
  };

  const newAllowed = await getHealth(env, { Origin: "https://new.example.com" });
  assert.equal(
    newAllowed.headers.get("access-control-allow-origin"),
    "https://new.example.com",
  );

  // legacy 值在新名存在時不應再被採用 → legacy origin 被擋。
  const legacyBlocked = await getHealth(env, {
    Origin: "https://legacy.example.com",
  });
  assert.equal(
    legacyBlocked.headers.get("access-control-allow-origin"),
    null,
  );
});

test("空清單（dev）：任意 browser origin 放行（allow-all 維持）", async () => {
  const env = {}; // 兩個變數都未設 → 空清單

  const res = await getHealth(env, { Origin: "https://anything.example.com" });
  assert.equal(res.status, 200);
  assert.equal(
    res.headers.get("access-control-allow-origin"),
    "https://anything.example.com",
  );
});

test("無 Origin header（curl / Flutter 原生 HTTP）一律放行", async () => {
  // 有設白名單時，仍須放行不帶 Origin 的請求（禁區：server.js line 171）。
  const withList = await getHealth(
    { CORS_ALLOWED_ORIGINS: "https://app.example.com" },
    {},
  );
  assert.equal(withList.status, 200);

  // 空清單時亦放行不帶 Origin 的請求。
  const emptyList = await getHealth({}, {});
  assert.equal(emptyList.status, 200);
});
