const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

class TaigiAsrError extends Error {
  constructor(code, message, status = 500) {
    super(message);
    this.name = "TaigiAsrError";
    this.code = code;
    this.status = status;
  }
}

function isTaigiAsrEnabled(env = process.env) {
  return String(env.TAIGI_ASR_ENABLED || "").toLowerCase() === "true";
}

function ensureAvailable(env = process.env) {
  if (!isTaigiAsrEnabled(env)) {
    throw new TaigiAsrError(
      "TAIGI_ASR_UNAVAILABLE",
      "Taigi ASR service is not configured",
      503,
    );
  }
}

async function transcribeTaigiAudio({
  audioPath,
  originalFilename = "",
  mimeType = "",
  env = process.env,
} = {}) {
  ensureAvailable(env);
  if (!audioPath || !fs.existsSync(audioPath)) {
    throw new TaigiAsrError("TAIGI_ASR_AUDIO_MISSING", "Audio file is missing", 400);
  }

  const provider = String(env.TAIGI_ASR_PROVIDER || "python").toLowerCase();
  if (provider === "test" && env.NODE_ENV === "test") {
    return {
      transcript: env.TAIGI_ASR_TEST_TRANSCRIPT || "",
      confidence: Number(env.TAIGI_ASR_TEST_CONFIDENCE || 0.8),
      language: "taigi",
      source: "taigi-asr",
    };
  }

  const normalizedPath = await normalizeAudioForAsr(audioPath, env);
  try {
    if (provider === "python") {
      return await transcribeWithPython({
        audioPath: normalizedPath,
        originalFilename,
        mimeType,
        env,
      });
    }
    throw new TaigiAsrError(
      "TAIGI_ASR_UNAVAILABLE",
      "Taigi ASR provider is not configured",
      503,
    );
  } finally {
    if (normalizedPath !== audioPath) {
      fs.unlink(normalizedPath, () => {});
    }
  }
}

async function normalizeAudioForAsr(audioPath, env = process.env) {
  const ffmpeg = env.FFMPEG_PATH || "ffmpeg";
  const outPath = path.join(
    os.tmpdir(),
    `taigi_asr_${Date.now()}_${Math.random().toString(16).slice(2)}.wav`,
  );
  try {
    await runCommand(ffmpeg, [
      "-y",
      "-i",
      audioPath,
      "-ac",
      "1",
      "-ar",
      "16000",
      "-f",
      "wav",
      outPath,
    ]);
    return outPath;
  } catch (error) {
    fs.unlink(outPath, () => {});
    throw new TaigiAsrError(
      "TAIGI_ASR_AUDIO_CONVERT_FAILED",
      "Audio conversion failed. Please install ffmpeg.",
      500,
    );
  }
}

async function transcribeWithPython({
  audioPath,
  originalFilename = "",
  mimeType = "",
  env = process.env,
}) {
  const python = env.TAIGI_ASR_PYTHON || "python3";
  const script = env.TAIGI_ASR_SCRIPT ||
    path.join(__dirname, "..", "scripts", "transcribe_taigi.py");
  const model = env.TAIGI_ASR_MODEL || "NUTN-KWS/Whisper-Taiwanese-model-v0.5";
  const stdout = await runCommand(python, [
    script,
    "--audio",
    audioPath,
    "--model",
    model,
    "--original-filename",
    originalFilename,
    "--mime-type",
    mimeType,
  ]);
  let decoded;
  try {
    decoded = JSON.parse(stdout);
  } catch (_) {
    throw new TaigiAsrError(
      "TAIGI_ASR_PROVIDER_ERROR",
      "Taigi ASR provider returned invalid output",
      502,
    );
  }
  if (decoded.error) {
    throw new TaigiAsrError(
      decoded.error || "TAIGI_ASR_PROVIDER_ERROR",
      decoded.message || "Taigi ASR provider failed",
      decoded.error === "TAIGI_ASR_UNAVAILABLE" ? 503 : 502,
    );
  }
  return {
    transcript: String(decoded.transcript || "").trim(),
    confidence: Number(decoded.confidence || 0),
    language: "taigi",
    source: "taigi-asr",
  };
}

function runCommand(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve(stdout.trim());
        return;
      }
      reject(new Error(stderr.trim() || `Command failed with code ${code}`));
    });
  });
}

module.exports = {
  TaigiAsrError,
  isTaigiAsrEnabled,
  transcribeTaigiAudio,
  normalizeAudioForAsr,
};
