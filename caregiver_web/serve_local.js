#!/usr/bin/env node
//
// caregiver_web 本機開發伺服器（同源 + /api 反向代理）。
//
// 問題：index.html 正式預設指向已部署後端（Render）。本機 demo 時，手機 App 與
//       長者端把 Care Alert / 任務寫進「本機後端」（預設 http://127.0.0.1:3001），
//       管理者網頁若還連 Render，就會看到「暫時連不上後端」或讀到不同份資料。
//       直接讓瀏覽器跨網域打本機後端又會被 CORS 擋（後端只放行 .env 白名單 origin）。
//
// 解法：用「同一個本機 origin」同時服務靜態網頁，並把 /api 與 /health 反向代理到
//       本機後端（server-to-server，不受瀏覽器 CORS 限制）。瀏覽器只跟本伺服器同源
//       對話，毋需修改 .env，也不必重啟後端。
//
// 用法：
//   node caregiver_web/serve_local.js
//   # 預設 http://localhost:5502，後端 http://127.0.0.1:3001
//   PORT=5510 BACKEND_URL=http://127.0.0.1:3001 node caregiver_web/serve_local.js
//
// 前置：本機後端要先啟動（手機 App 用的同一個）：
//   cd backend/stt_proxy && HOST=0.0.0.0 npm start

"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { URL } = require("url");

const PORT = Number(process.env.PORT || 5502);
const BACKEND_URL = process.env.BACKEND_URL || "http://127.0.0.1:3001";
const ROOT = __dirname;

const backend = new URL(BACKEND_URL);

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".webmanifest": "application/manifest+json",
};

function isApiPath(url) {
  return url === "/health" || url === "/api" || url.startsWith("/api/");
}

// /api、/health → 反向代理到本機後端（保留 method / headers / body）。
function proxyToBackend(req, res) {
  const options = {
    protocol: backend.protocol,
    hostname: backend.hostname,
    port: backend.port || (backend.protocol === "https:" ? 443 : 80),
    method: req.method,
    path: req.url,
    headers: { ...req.headers, host: backend.host },
  };
  const lib = backend.protocol === "https:" ? require("https") : http;
  const proxyReq = lib.request(options, (proxyRes) => {
    res.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
    proxyRes.pipe(res);
  });
  proxyReq.on("error", () => {
    res.writeHead(502, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        success: false,
        error: "backend_unreachable",
        message: `無法連到本機後端 ${BACKEND_URL}，請確認後端已用 HOST=0.0.0.0 啟動。`,
      }),
    );
  });
  req.pipe(proxyReq);
}

// 其餘路徑 → 服務 caregiver_web 靜態檔（防目錄跳脫）。
function serveStatic(req, res) {
  let pathname = "/index.html";
  try {
    pathname = decodeURIComponent(new URL(req.url, "http://x").pathname);
  } catch {
    pathname = "/index.html";
  }
  if (pathname === "/" || pathname === "") pathname = "/index.html";

  const filePath = path.join(ROOT, pathname);
  if (!filePath.startsWith(ROOT + path.sep) && filePath !== ROOT) {
    res.writeHead(403);
    res.end("forbidden");
    return;
  }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("not found");
      return;
    }
    res.writeHead(200, {
      "Content-Type": MIME[path.extname(filePath)] || "application/octet-stream",
    });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  if (isApiPath(req.url)) return proxyToBackend(req, res);
  return serveStatic(req, res);
});

server.listen(PORT, () => {
  console.log("──────────────────────────────────────────────");
  console.log(`  管理者網頁： http://localhost:${PORT}`);
  console.log(`  /api 反向代理 → ${BACKEND_URL}`);
  console.log("  後端請先啟動：cd backend/stt_proxy && HOST=0.0.0.0 npm start");
  console.log("──────────────────────────────────────────────");
});
