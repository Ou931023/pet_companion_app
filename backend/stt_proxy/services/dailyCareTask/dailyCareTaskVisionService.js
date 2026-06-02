// CR-0025 日常照護任務 AI 影像確認服務。
//
// 重要安全界線（見 CR SECTION 03）：
// - AI 只確認「照片中是否有任務相關物件 / 場景」，**絕不**判斷藥物是否正確、
//   劑量是否正確、或使用者是否真的吃下/喝完/運動達標。
// - 不確定 / 失敗 / 缺 key → 一律回 uncertain + reviewRequired=true（送人工查看），
//   **永不** fake passed。
// - 任何例外都被吞掉並回 uncertain，不讓 server crash。
//
// 輸出（與 store.normalizeVerification 對齊）：
//   { verificationStatus: 'passed'|'uncertain'|'failed', confidence, reason,
//     detectedObjects: string[], reviewRequired: boolean }

const fs = require("fs/promises");
const OpenAI = require("openai");

// 各任務類型的通過信心門檻（見 CR SECTION 07D）。
const CONFIDENCE_THRESHOLDS = {
  medication: 0.7,
  hydration: 0.7,
  exercise: 0.65,
};

// 給模型看的「該找什麼」描述。
const TYPE_HINTS = {
  medication: "藥包、藥盒、藥丸、藥袋、藥杯或其他服藥相關物件",
  hydration: "水杯、水瓶、飲水容器或正在喝水的畫面",
  exercise: "散步、戶外活動、運動器材、健走或運動姿勢等活動場景",
};

const UNCERTAIN_FALLBACK_REASON = "影像確認暫時無法完成，已送照護人員查看";

let sharedClient;

function getClient() {
  if (!process.env.OPENAI_API_KEY) return null;
  if (!sharedClient) {
    sharedClient = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }
  return sharedClient;
}

function normalizeTaskType(taskType) {
  const raw = (taskType || "").toString().trim().toLowerCase();
  if (raw === "walk") return "exercise";
  if (CONFIDENCE_THRESHOLDS[raw]) return raw;
  return "medication";
}

function uncertainResult(reason) {
  return {
    verificationStatus: "uncertain",
    confidence: 0,
    reason: reason || UNCERTAIN_FALLBACK_REASON,
    detectedObjects: [],
    reviewRequired: true,
  };
}

function mimeToDataUrlPrefix(mimeType) {
  const mt = (mimeType || "").toString().toLowerCase();
  if (mt.includes("png")) return "data:image/png;base64,";
  if (mt.includes("webp")) return "data:image/webp;base64,";
  if (mt.includes("heic") || mt.includes("heif")) return "data:image/heic;base64,";
  return "data:image/jpeg;base64,";
}

async function imagePathToDataUrl(imagePath, mimeType) {
  const buffer = await fs.readFile(imagePath);
  return `${mimeToDataUrlPrefix(mimeType)}${buffer.toString("base64")}`;
}

function buildPrompt(taskType) {
  const hint = TYPE_HINTS[taskType] || TYPE_HINTS.medication;
  return [
    "你是一個照護任務的照片輔助檢查員。",
    `這張照片應該是長者完成「${taskType}」任務的證明，請判斷照片中是否出現：${hint}。`,
    "重要限制：你只負責判斷照片中是否有相關物件或場景，",
    "絕對不要宣稱藥物正確、劑量正確、或使用者真的吃下/喝完/運動達標。",
    "請只回傳 JSON，格式：",
    '{"match": true/false, "confidence": 0~1 的數字, "detectedObjects": ["物件1","物件2"], "reason": "一句話說明（繁體中文、白話、不要醫療診斷）"}',
    "match 代表照片中是否明確出現該任務相關物件/場景；confidence 是你的把握程度。",
  ].join("\n");
}

function parseModelJson(content) {
  if (!content) return null;
  const text = content.toString().trim();
  // 容錯：模型可能包了 ```json 區塊或多餘文字，抓第一個 { ... }。
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try {
    return JSON.parse(match[0]);
  } catch (_) {
    return null;
  }
}

// 把模型輸出（match/confidence）對應到 passed/uncertain/failed。
function interpret(taskType, parsed) {
  if (!parsed || typeof parsed !== "object") {
    return uncertainResult(UNCERTAIN_FALLBACK_REASON);
  }
  const threshold = CONFIDENCE_THRESHOLDS[taskType] ?? 0.7;
  const confidence = Number(parsed.confidence);
  const safeConfidence = Number.isFinite(confidence)
    ? Math.max(0, Math.min(1, confidence))
    : 0;
  const detectedObjects = Array.isArray(parsed.detectedObjects)
    ? parsed.detectedObjects.filter((o) => typeof o === "string")
    : [];
  const reason =
    typeof parsed.reason === "string" && parsed.reason.trim()
      ? parsed.reason.trim()
      : "";
  const match = parsed.match === true;

  // 把握度不足 → uncertain（不論 match 與否），交人工。
  if (safeConfidence < threshold) {
    return {
      verificationStatus: "uncertain",
      confidence: safeConfidence,
      reason: reason || "這張照片看不太清楚，先送給照護人員確認。",
      detectedObjects,
      reviewRequired: true,
    };
  }

  if (match) {
    return {
      verificationStatus: "passed",
      confidence: safeConfidence,
      reason: reason || "照片看起來有相關物品，先幫你記錄完成。",
      detectedObjects,
      reviewRequired: false,
    };
  }

  // 有把握「不符合」→ failed，但仍送人工查看（避免誤判）。
  return {
    verificationStatus: "failed",
    confidence: safeConfidence,
    reason: reason || "這張照片好像不太符合任務，我們再確認一下。",
    detectedObjects,
    reviewRequired: true,
  };
}

// 主入口。input: { taskType, imagePath, mimeType }
// options（測試/注入）：{ client, imageDataUrl, model }
async function verifyProof(input = {}, options = {}) {
  const taskType = normalizeTaskType(input.taskType);
  const client = options.client || getClient();
  if (!client) {
    // 缺 OPENAI_API_KEY：不 crash、不 fake pass。
    return uncertainResult(UNCERTAIN_FALLBACK_REASON);
  }

  try {
    const dataUrl =
      options.imageDataUrl ||
      (await imagePathToDataUrl(input.imagePath, input.mimeType));
    const model =
      options.model || process.env.DAILY_CARE_VISION_MODEL || "gpt-4o-mini";

    const response = await client.chat.completions.create({
      model,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: buildPrompt(taskType) },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        },
      ],
    });

    const content = response?.choices?.[0]?.message?.content;
    const parsed = parseModelJson(content);
    return interpret(taskType, parsed);
  } catch (error) {
    console.error("[daily-care-vision] verify failed, defaulting to uncertain", {
      error: error?.message || error,
    });
    return uncertainResult(UNCERTAIN_FALLBACK_REASON);
  }
}

module.exports = {
  verifyProof,
  // 測試/工具用
  interpret,
  normalizeTaskType,
  uncertainResult,
  CONFIDENCE_THRESHOLDS,
  UNCERTAIN_FALLBACK_REASON,
};
