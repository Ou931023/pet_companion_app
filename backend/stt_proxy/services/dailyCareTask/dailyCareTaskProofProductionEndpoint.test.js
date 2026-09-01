"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test, afterEach } = require("node:test");

process.env.NODE_ENV = "test";
process.env.OPENAI_API_KEY = "";
process.env.PGVECTOR_ENABLED = "false";
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../../server");
const dailyCareStore = require("./dailyCareTaskStore");
const residentAuth = require("../auth/residentCallerContext");
const adminAuth = require("../admin/adminAuthContext");
const authz = require("../admin/authorizationService");

const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_Z = "99999999-9999-9999-9999-999999999999";
const RESIDENT_HEADERS = { Authorization: "Bearer resident-a-token" };
const CAREGIVER_HEADERS = { Authorization: "Bearer caregiver-a-token" };

function firebaseStub() {
  const tokenToUid = {
    "resident-a-token": "fb-resident-a",
    "caregiver-a-token": "fb-caregiver-a",
  };
  return {
    isConfigured: () => true,
    verifyIdToken: async (token) =>
      tokenToUid[token] ? { uid: tokenToUid[token] } : null,
  };
}

function taskRow(status = "pending") {
  return {
    id: "task-a",
    elder_id: ELDER_A,
    title: "喝水",
    type: "hydration",
    description: "",
    scheduled_time: "10:00",
    due_at: null,
    status,
    proof_required: true,
    created_at: new Date("2026-08-30T00:00:00.000Z"),
    updated_at: new Date("2026-08-30T00:00:00.000Z"),
  };
}

function productionPg({ caregiverRole = "primary", legacyProofPath = null } = {}) {
  const submissions = new Map();
  return {
    isPostgresAvailable: async () => true,
    query: async (text, params = []) => {
      if (/FROM users WHERE firebase_uid/i.test(text)) {
        if (params[0] === "fb-resident-a") {
          return {
            rows: [
              {
                id: "resident-user-a",
                role: "resident",
                status: "active",
                elder_id: ELDER_A,
              },
            ],
          };
        }
        if (params[0] === "fb-caregiver-a") {
          return {
            rows: [{ id: "caregiver-a", role: "caregiver", status: "active" }],
          };
        }
        return { rows: [] };
      }
      if (/resident_caregiver_links/i.test(text)) {
        if (/role IN \('primary', 'secondary'\)/i.test(text)) {
          return caregiverRole === "viewer"
            ? { rows: [] }
            : { rows: [{ role: caregiverRole }] };
        }
        return { rows: [{ elder_id: ELDER_A, role: caregiverRole }] };
      }
      if (/SELECT \* FROM daily_care_tasks WHERE id = \$1 FOR UPDATE/i.test(text)) {
        return { rows: params[0] === "task-a" ? [taskRow()] : [] };
      }
      if (/SELECT \* FROM daily_care_tasks WHERE id = \$1/i.test(text)) {
        return { rows: params[0] === "task-a" ? [taskRow()] : [] };
      }
      if (/INSERT INTO daily_care_task_submissions/i.test(text)) {
        submissions.set(params[0], {
          id: params[0],
          task_id: params[1],
          elder_id: params[2],
          proof_image_path: params[3],
          proof_image_bytes: params[4],
          proof_mime_type: params[5],
          submitted_at: params[6],
          status: params[7],
          verification_json: JSON.parse(params[8]),
          note: params[9],
        });
        return { rows: [] };
      }
      if (/UPDATE daily_care_tasks SET status/i.test(text)) {
        return { rows: [taskRow(params[1])] };
      }
      if (/SELECT \* FROM daily_care_task_submissions WHERE id = \$1/i.test(text)) {
        if (params[0] === "legacy-proof" && legacyProofPath) {
          return {
            rows: [
              {
                id: params[0],
                task_id: "task-a",
                elder_id: ELDER_A,
                proof_image_path: legacyProofPath,
                proof_image_bytes: null,
                proof_mime_type: "image/jpeg",
                submitted_at: new Date("2026-08-30T00:00:00.000Z"),
                status: "needs_review",
                verification_json: {},
                note: "",
              },
            ],
          };
        }
        if (params[0] === "cross-resident-proof") {
          return {
            rows: [
              {
                id: params[0],
                task_id: "task-z",
                elder_id: ELDER_Z,
                proof_image_path: null,
                proof_image_bytes: Buffer.from([9, 9, 9]),
                proof_mime_type: "image/jpeg",
                submitted_at: new Date("2026-08-30T00:00:00.000Z"),
                status: "needs_review",
                verification_json: {},
                note: "",
              },
            ],
          };
        }
        const row = submissions.get(params[0]);
        return { rows: row ? [row] : [] };
      }
      return { rows: [] };
    },
  };
}

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function withProductionRequest(run) {
  const originalAppEnv = process.env.APP_ENV;
  try {
    process.env.APP_ENV = "production";
    return await run();
  } finally {
    if (originalAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = originalAppEnv;
  }
}

afterEach(() => {
  dailyCareStore.setPgForTest(null);
  residentAuth.setFirebaseAdminForTest(null);
  residentAuth.setPgForTest(null);
  adminAuth.setFirebaseAdminForTest(null);
  adminAuth.setPgForTest(null);
  authz.setPgForTest(null);
});

test("production viewer 可讀 proof，但不可 PATCH 任務狀態", async () => {
  const pg = productionPg({ caregiverRole: "viewer" });
  const firebase = firebaseStub();
  dailyCareStore.setPgForTest(pg);
  adminAuth.setFirebaseAdminForTest(firebase);
  adminAuth.setPgForTest(pg);
  authz.setPgForTest(pg);

  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await withProductionRequest(() =>
      fetch(`${baseUrl}/api/daily-care-tasks/task-a/status`, {
        method: "PATCH",
        headers: {
          ...CAREGIVER_HEADERS,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ status: "completed" }),
      }),
    );

    assert.equal(response.status, 403);
    assert.deepEqual(await response.json(), {
      success: false,
      error: "forbidden",
    });
  } finally {
    server.close();
  }
});

test("production DB 照片寫入後，授權 caregiver 可讀、跨住民 403，JSON 不洩漏 bytes/path", async () => {
  const pg = productionPg();
  const firebase = firebaseStub();
  dailyCareStore.setPgForTest(pg);
  residentAuth.setFirebaseAdminForTest(firebase);
  residentAuth.setPgForTest(pg);
  adminAuth.setFirebaseAdminForTest(firebase);
  adminAuth.setPgForTest(pg);
  authz.setPgForTest(pg);

  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const photo = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
    const form = new FormData();
    form.append("photo", new Blob([photo], { type: "image/jpeg" }), "proof.jpg");

    const submitted = await withProductionRequest(() =>
      fetch(`${baseUrl}/api/daily-care-tasks/task-a/submit`, {
        method: "POST",
        headers: RESIDENT_HEADERS,
        body: form,
      }),
    );
    assert.equal(submitted.status, 200);
    const body = await submitted.json();
    assert.equal(body.success, true);
    assert.equal(body.submission.hasProofImage, true);
    assert.equal(Object.hasOwn(body.submission, "proofImagePath"), false);
    assert.equal(Object.hasOwn(body.submission, "proofImageBytes"), false);

    const proof = await withProductionRequest(() =>
      fetch(
        `${baseUrl}/api/daily-care-tasks/proof/${body.submission.id}`,
        { headers: CAREGIVER_HEADERS },
      ),
    );
    assert.equal(proof.status, 200);
    assert.equal(proof.headers.get("cache-control"), "private, no-store");
    assert.deepEqual(Buffer.from(await proof.arrayBuffer()), photo);

    const forbidden = await withProductionRequest(() =>
      fetch(
        `${baseUrl}/api/daily-care-tasks/proof/cross-resident-proof`,
        { headers: CAREGIVER_HEADERS },
      ),
    );
    assert.equal(forbidden.status, 403);
    assert.deepEqual(await forbidden.json(), {
      success: false,
      error: "forbidden",
    });
  } finally {
    server.close();
  }
});

test("legacy proof path 成功回傳時同樣禁止快取並啟用 nosniff", async () => {
  const uploadsRoot = path.join(__dirname, "..", "..", "uploads");
  const legacyProofPath = path.join(
    uploadsRoot,
    `legacy-proof-${process.pid}-${Date.now()}.jpg`,
  );
  const photo = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
  fs.mkdirSync(uploadsRoot, { recursive: true });
  fs.writeFileSync(legacyProofPath, photo);

  const pg = productionPg({ legacyProofPath });
  const firebase = firebaseStub();
  dailyCareStore.setPgForTest(pg);
  adminAuth.setFirebaseAdminForTest(firebase);
  adminAuth.setPgForTest(pg);
  authz.setPgForTest(pg);

  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const proof = await withProductionRequest(() =>
      fetch(`${baseUrl}/api/daily-care-tasks/proof/legacy-proof`, {
        headers: CAREGIVER_HEADERS,
      }),
    );

    assert.equal(proof.status, 200);
    assert.equal(proof.headers.get("cache-control"), "private, no-store");
    assert.equal(proof.headers.get("x-content-type-options"), "nosniff");
    assert.deepEqual(Buffer.from(await proof.arrayBuffer()), photo);
  } finally {
    server.close();
    fs.rmSync(legacyProofPath, { force: true });
  }
});
