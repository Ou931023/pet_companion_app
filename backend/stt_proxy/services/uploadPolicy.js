const path = require("node:path");
const os = require("node:os");

const STT_MAX_BYTES = 25_000_000;
function uploadDirectory(name) {
  return path.join(os.tmpdir(), process.env.NODE_ENV === "test" ? `${name}-${process.pid}` : name);
}
function multipartLimits(fileSize) {
  return {
    fileSize, files: 1, fields: 8, parts: 9,
    fieldNameSize: 100, fieldSize: 4096,
    fieldNestingDepth: 2, fieldArrayIndexLimit: 20,
  };
}
function taigiMaxBytes(configured) {
  const bytes = Number(configured);
  return Number.isSafeInteger(bytes) && bytes > 0
    ? Math.min(bytes, STT_MAX_BYTES) : 10 * 1024 * 1024;
}
const PHOTO_TYPES = {
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
  ".webp": "image/webp", ".heic": "image/heic", ".heif": "image/heif",
};
function photoMimeType(file) {
  const mime = String(file.mimetype || "").toLowerCase();
  if (Object.values(PHOTO_TYPES).includes(mime)) return mime;
  return mime === "application/octet-stream"
    ? PHOTO_TYPES[path.extname(file.originalname || "").toLowerCase()] || null
    : null;
}
module.exports = { STT_MAX_BYTES, multipartLimits, taigiMaxBytes, photoMimeType, uploadDirectory };
