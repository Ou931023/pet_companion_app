"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const OpenAI = require("openai");
const { chatModelParameters, fileTranscriptionParameters, realtimeModelParameters, completionContent } = require("./openAiModelParameters");
const { generateCompanionReply } = require("./companionChatService");
const { verifyProof } = require("./dailyCareTask/dailyCareTaskVisionService");

test("Luna explicitly disables reasoning and bounds completion; legacy overrides keep their wire shape", () => {
  assert.deepEqual(chatModelParameters("gpt-6-luna", { temperature: 0, maxTokens: 220 }), {
    model: "gpt-6-luna", temperature: 0, reasoning_effort: "none", max_completion_tokens: 220,
  });
  assert.equal(chatModelParameters("gpt-6-luna").max_completion_tokens, 2048);
  assert.deepEqual(chatModelParameters("gpt-4o-mini", { temperature: 0.2, maxTokens: 220 }), {
    model: "gpt-4o-mini", temperature: 0.2, max_tokens: 220,
  });
  assert.deepEqual(chatModelParameters("operator-override"), { model: "operator-override" });
});

test("recorded STT uses automatic language detection or explicit supported hints, never singular language", () => {
  assert.deepEqual(fileTranscriptionParameters({}), { model: "gpt-transcribe", response_format: "json" });
  assert.deepEqual(fileTranscriptionParameters({ STT_LANGUAGES: " zh-tw, en,zh-tw " }).languages, ["zh-tw", "en"]);
  for (const hints of ["nan", "en,", "unsupported"]) {
    assert.throws(() => fileTranscriptionParameters({ STT_LANGUAGES: hints }), /Unsupported/);
  }
  assert.deepEqual(fileTranscriptionParameters({ STT_MODEL: "gpt-4o-mini-transcribe", STT_LANGUAGES: "nan" }), {
    model: "gpt-4o-mini-transcribe", response_format: "json",
  });
});

test("reasoning and response cap apply only to the explicitly selected GA voice model", () => {
  assert.deepEqual(realtimeModelParameters("gpt-realtime-2.1"), {
    model: "gpt-realtime-2.1", reasoning: { effort: "low" }, max_output_tokens: 1024,
  });
  assert.deepEqual(realtimeModelParameters("gpt-realtime"), { model: "gpt-realtime" });
});

for (const finish_reason of ["stop", undefined]) {
  test(`complete content remains compatible with finish_reason=${finish_reason}`, () => {
    assert.equal(completionContent({ choices: [{ finish_reason, message: { content: "synthetic" } }] }), "synthetic");
  });
}

const unsafeChoices = [
  { finish_reason: "length", message: { content: '{"match":true,"confidence":1}' } },
  { finish_reason: "content_filter", message: { content: '{"match":true,"confidence":1}' } },
  { finish_reason: "stop", message: { content: '{"match":true,"confidence":1}', refusal: "synthetic refusal" } },
];
for (const choice of unsafeChoices) {
  test(`incomplete/refused content is rejected before chat or image success: ${choice.message.refusal || choice.finish_reason}`, async () => {
    const response = { choices: [choice] };
    assert.throws(() => completionContent(response), /Incomplete or refused/);
    const client = { chat: { completions: { create: async () => response } } };
    const chat = await generateCompanionReply({ userText: "synthetic" }, { client });
    assert.deepEqual(chat, { success: false, error: "openai_unavailable" });
    const image = await verifyProof({ taskType: "medication" }, { client, imageDataUrl: "data:image/jpeg;base64,AAAA" });
    assert.equal(image.verificationStatus, "uncertain");
    assert.equal(image.reviewRequired, true);
  });
}

test("chat and image callers use bounded Luna defaults and preserve image/JSON input", async () => {
  const requests = [];
  const client = { chat: { completions: { create: async request => {
    requests.push(request);
    return { choices: [{ finish_reason: "stop", message: { content: '{"match":true,"confidence":0.95}' } }] };
  } } } };
  await generateCompanionReply({ userText: "synthetic" }, { client });
  await verifyProof({ taskType: "medication" }, { client, imageDataUrl: "data:image/jpeg;base64,AAAA" });
  assert.equal(requests[0].model, "gpt-6-luna");
  assert.equal(requests[0].max_completion_tokens, 220);
  assert.equal(requests[1].max_completion_tokens, 1024);
  assert.deepEqual(requests[1].response_format, { type: "json_object" });
  assert.equal(requests[1].messages[0].content[1].type, "image_url");
});

test("installed OpenAI SDK serializes Luna JSON and GPT-Transcribe multipart without any network", async () => {
  const requests = [];
  const client = new OpenAI({ apiKey: "synthetic-not-a-key", maxRetries: 0, fetch: async (url, init) => {
    let body = "";
    if (typeof init.body === "string") body = init.body;
    else for await (const chunk of init.body) body += Buffer.from(chunk).toString("utf8");
    requests.push({ url: String(url), body });
    return new Response(JSON.stringify(String(url).endsWith("/audio/transcriptions")
      ? { text: "synthetic transcript", languages: ["en"] }
      : { choices: [{ message: { content: "{}" }, finish_reason: "stop" }] }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  } });
  await client.chat.completions.create({ ...chatModelParameters("gpt-6-luna", { temperature: 0 }),
    response_format: { type: "json_object" }, messages: [{ role: "user", content: "synthetic JSON" }] });
  const json = JSON.parse(requests[0].body);
  assert.equal(json.reasoning_effort, "none");
  assert.equal(json.max_completion_tokens, 2048);
  assert.equal(json.max_tokens, undefined);
  assert.deepEqual(json.response_format, { type: "json_object" });
  const file = await OpenAI.toFile(Buffer.from("synthetic audio fixture"), "synthetic.wav");
  const result = await client.audio.transcriptions.create({ file,
    ...fileTranscriptionParameters({ STT_LANGUAGES: "zh-tw,en" }) });
  assert.equal(result.text, "synthetic transcript");
  assert.match(requests[1].body, /name="model"\r\n\r\ngpt-transcribe/);
  assert.equal((requests[1].body.match(/name="languages\[\]"/g) || []).length, 2);
  assert.match(requests[1].body, /\r\nzh-tw\r\n/);
  assert.match(requests[1].body, /\r\nen\r\n/);
  assert.doesNotMatch(requests[1].body, /name="language"/);
  assert.match(requests[1].body, /filename="synthetic.wav"/);
  await client.audio.transcriptions.create({ file, ...fileTranscriptionParameters({ STT_MODEL: "gpt-4o-mini-transcribe" }) });
  assert.match(requests[2].body, /gpt-4o-mini-transcribe/);
  assert.doesNotMatch(requests[2].body, /name="languages/);
});
