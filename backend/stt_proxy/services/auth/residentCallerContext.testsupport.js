// CR-0045：resident-caller 身分的測試 stub 安裝器（非 .test.js → node --test 不會當測試執行）。
//
// 用途：讓 /notify 的 HTTP 層測試以「stub firebaseAdmin + mock pg」安裝 resident caller 身分，
// 免真 Firebase 金鑰 / 真 DB。比照 careAlertAuthScopeEndpoint.test.js 的 caregiver 安裝模式。
//
// residents: { [bearerToken]: { uid, elderId, userId?, role?, status? } }
//   - bearerToken：HTTP Authorization: Bearer <token> 的字面值。
//   - uid：verifyIdToken(token) 解出的 firebase_uid。
//   - elderId：users.elder_id（server 會以此蓋寫 alert.elderId）。
// 回傳 restore()：還原 residentCallerContext 的 firebaseAdmin / pg seam。

"use strict";

const residentCaller = require("./residentCallerContext");

function installResidentCallerStub(residents = {}) {
  const byToken = residents;
  const byUid = {};
  for (const token of Object.keys(byToken)) {
    const r = byToken[token];
    byUid[r.uid] = r;
  }

  residentCaller.setFirebaseAdminForTest({
    isConfigured: () => true,
    verifyIdToken: async (token) => {
      const r = byToken[token];
      return r ? { uid: r.uid } : null;
    },
  });

  residentCaller.setPgForTest({
    isPostgresAvailable: async () => true,
    query: async (text, params) => {
      const uid = params && params[0];
      const r = byUid[uid];
      if (!r) return { rows: [] };
      return {
        rows: [
          {
            id: r.userId || r.uid,
            role: r.role || "resident",
            status: r.status || "active",
            elder_id: r.elderId,
          },
        ],
      };
    },
  });

  return function restore() {
    residentCaller.setFirebaseAdminForTest(null);
    residentCaller.setPgForTest(null);
  };
}

module.exports = { installResidentCallerStub };
