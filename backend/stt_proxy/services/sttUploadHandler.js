const fs = require("node:fs");

// Injection keeps failure/abort coverage local: tests never call a real provider.
function createSttUploadHandler({ client, isConfigured }) {
  return async (req, res) => {
    const controller = new AbortController();
    let audioStream;
    const abort = () => { if (!res.writableEnded) controller.abort(); };
    res.once("close", abort);
    try {
      if (!isConfigured()) {
        return res.status(500).json({ success: false, code: "missing_api_key", message: "Missing OPENAI_API_KEY" });
      }
      if (!req.file) {
        return res.status(400).json({ success: false, message: "audio file is required" });
      }
      if (res.destroyed) return;
      audioStream = fs.createReadStream(req.file.path);
      const result = await client.audio.transcriptions.create({
        file: audioStream, model: "gpt-4o-transcribe", response_format: "json",
      }, { signal: controller.signal });
      if (res.destroyed) return;
      const text = (result.text || "").trim();
      if (!text) return res.status(422).json({ success: false, message: "Empty transcript" });
      return res.json({ success: true, text });
    } catch (_) {
      if (!res.destroyed) return res.status(500).json({ success: false, message: "STT failed", error: "Transcription unavailable" });
    } finally {
      res.removeListener("close", abort);
      if (audioStream) {
        // Wait for the descriptor to close before unlinking, including aborts.
        await new Promise((resolve) => {
          if (audioStream.closed) return resolve();
          audioStream.once("close", resolve);
          audioStream.on("error", () => {});
          audioStream.destroy();
        });
      }
      if (req.file) await fs.promises.unlink(req.file.path).catch(() => {});
    }
  };
}
module.exports = { createSttUploadHandler };
