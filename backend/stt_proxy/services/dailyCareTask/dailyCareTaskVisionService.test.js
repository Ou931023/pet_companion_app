const assert = require("node:assert/strict");
const test = require("node:test");

// 強制「無 OPENAI_API_KEY」路徑可被確定性測試（壓過 shell / .env 的 key）。
process.env.OPENAI_API_KEY = "";

const vision = require("./dailyCareTaskVisionService");

// 假 OpenAI client：回傳 chat.completions.create 的固定 JSON content。
function stubClient(jsonObj) {
  return {
    chat: {
      completions: {
        create: async () => ({
          choices: [{ message: { content: JSON.stringify(jsonObj) } }],
        }),
      },
    },
  };
}

const FAKE_IMAGE = "data:image/jpeg;base64,AAAA";

test("缺 OPENAI_API_KEY → uncertain、reviewRequired、不 fake passed", async () => {
  const result = await vision.verifyProof({
    taskType: "medication",
    imagePath: "/tmp/whatever.jpg",
  });
  assert.equal(result.verificationStatus, "uncertain");
  assert.equal(result.reviewRequired, true);
  assert.notEqual(result.verificationStatus, "passed");
  assert.equal(result.reason, vision.UNCERTAIN_FALLBACK_REASON);
});

test("吃藥：照片有藥盒、高信心 → passed", async () => {
  const result = await vision.verifyProof(
    { taskType: "medication" },
    {
      client: stubClient({
        match: true,
        confidence: 0.92,
        detectedObjects: ["藥盒", "藥丸"],
        reason: "看起來有藥品",
      }),
      imageDataUrl: FAKE_IMAGE,
    },
  );
  assert.equal(result.verificationStatus, "passed");
  assert.equal(result.reviewRequired, false);
  assert.deepEqual(result.detectedObjects, ["藥盒", "藥丸"]);
});

test("喝水：照片有水杯、高信心 → passed", async () => {
  const result = await vision.verifyProof(
    { taskType: "hydration" },
    {
      client: stubClient({ match: true, confidence: 0.8, detectedObjects: ["水杯"] }),
      imageDataUrl: FAKE_IMAGE,
    },
  );
  assert.equal(result.verificationStatus, "passed");
});

test("運動：活動場景、信心 0.66（> 0.65 門檻）→ passed", async () => {
  const result = await vision.verifyProof(
    { taskType: "exercise" },
    {
      client: stubClient({ match: true, confidence: 0.66, detectedObjects: ["散步"] }),
      imageDataUrl: FAKE_IMAGE,
    },
  );
  assert.equal(result.verificationStatus, "passed");
});

test("信心不足（低於門檻）→ uncertain，不論 match", async () => {
  const result = await vision.verifyProof(
    { taskType: "medication" },
    {
      client: stubClient({ match: true, confidence: 0.4 }),
      imageDataUrl: FAKE_IMAGE,
    },
  );
  assert.equal(result.verificationStatus, "uncertain");
  assert.equal(result.reviewRequired, true);
});

test("明確不符合、高信心 → failed（仍 reviewRequired，避免誤判）", async () => {
  const result = await vision.verifyProof(
    { taskType: "hydration" },
    {
      client: stubClient({ match: false, confidence: 0.9, reason: "看起來不是喝水" }),
      imageDataUrl: FAKE_IMAGE,
    },
  );
  assert.equal(result.verificationStatus, "failed");
  assert.equal(result.reviewRequired, true);
});

test("client 丟例外 → uncertain，不 crash", async () => {
  const throwingClient = {
    chat: {
      completions: {
        create: async () => {
          throw new Error("network down");
        },
      },
    },
  };
  const result = await vision.verifyProof(
    { taskType: "exercise" },
    { client: throwingClient, imageDataUrl: FAKE_IMAGE },
  );
  assert.equal(result.verificationStatus, "uncertain");
  assert.equal(result.reviewRequired, true);
});

test("模型回非 JSON / 空 → uncertain", async () => {
  const junkClient = {
    chat: {
      completions: {
        create: async () => ({ choices: [{ message: { content: "我不知道" } }] }),
      },
    },
  };
  const result = await vision.verifyProof(
    { taskType: "medication" },
    { client: junkClient, imageDataUrl: FAKE_IMAGE },
  );
  assert.equal(result.verificationStatus, "uncertain");
});

test("interpret 單元：confidence 會被夾在 0~1", () => {
  const r = vision.interpret("medication", { match: true, confidence: 5 });
  assert.equal(r.verificationStatus, "passed");
  assert.equal(r.confidence, 1);
});
