// CR-0029：管理者端 API 權限檢查中介層。
//
// Demo 階段以環境變數 ADMIN_API_TOKEN 做 Bearer token 驗證（fail-closed）：
//   - 沒有 Authorization header / 沒有 token → 401 missing_admin_token
//   - 後端未設定 ADMIN_API_TOKEN，或 token 不符 → 403 admin_permission_required
//
// 正式產品應改為 admin 登入 + JWT + role-based access control（見 docs/ADMIN_USER_MANAGEMENT.md）。
// 本中介層只負責「擋門」，不查資料庫、不回傳任何敏感資訊。

function extractBearerToken(authHeader) {
  const raw = (authHeader || "").toString().trim();
  if (!raw) return "";
  // 接受 "Bearer <token>"（大小寫不敏感）或直接帶 token。
  const match = raw.match(/^Bearer\s+(.+)$/i);
  return (match ? match[1] : raw).trim();
}

function requireAdmin(req, res, next) {
  const token = extractBearerToken(req.headers && req.headers.authorization);

  if (!token) {
    return res.status(401).json({ ok: false, error: "missing_admin_token" });
  }

  const expected = (process.env.ADMIN_API_TOKEN || "").toString();
  // fail-closed：未設定 expected（空字串）時一律拒絕，避免無門檻放行。
  if (!expected || token !== expected) {
    return res.status(403).json({ ok: false, error: "admin_permission_required" });
  }

  return next();
}

module.exports = requireAdmin;
module.exports.extractBearerToken = extractBearerToken;
