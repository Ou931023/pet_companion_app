"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

process.env.NODE_ENV = "test";
// require server 會載入 .env；此測試只驗證 prompt 字串組裝，完全不打 OpenAI。
// 清掉金鑰避免任何外呼或誤發通知的可能。
delete process.env.OPENAI_API_KEY;
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const { buildCompanionChatInstructions } = require("../server");

// 模擬 /api/companion/chat 端點對 memoryBlock 的組裝方式（CR-0049 inline 區塊）。
function buildMemoryBlock(summary) {
  return `以下是你自然記得的使用者近況：
${summary}
請自然地關心使用者，不要說「根據紀錄」或「資料庫顯示」。如果使用者不想聊這件事，請溫柔轉換話題。`;
}

test("petName 出現在 header；空字串時 fallback 「陪伴寶」", () => {
  const named = buildCompanionChatInstructions("小白", "", {});
  assert.ok(named.includes("你的名字是 小白。"), "應帶入指定寵物名");

  const empty = buildCompanionChatInstructions("", "", {});
  assert.ok(empty.includes("你的名字是 陪伴寶。"), "空名時應 fallback 陪伴寶");

  const blank = buildCompanionChatInstructions("   ", "", {});
  assert.ok(blank.includes("你的名字是 陪伴寶。"), "全空白名時應 fallback 陪伴寶");
});

test("情緒優先原則：先接住情緒再回應內容", () => {
  const prompt = buildCompanionChatInstructions("小白", "", {});
  assert.ok(
    prompt.includes("先接住長者當下的情緒，再回應他說的內容"),
    "persona 必須包含情緒優先原則",
  );
});

test("G1：無工具清單、無假裝執行 App 動作的承諾", () => {
  const prompt = buildCompanionChatInstructions("小白", "", {});
  // 不得帶入語音 persona 的工具對照表標題。
  assert.ok(!prompt.includes("意義對照表"), "不可包含工具意義對照表");
  // 不得帶入語音 persona 那些「肯定已執行」的承諾用語。
  assert.ok(!prompt.includes("幫你打給"), "不可指示模型肯定回『幫你打給X』");
  assert.ok(!prompt.includes("幫你寄信"), "不可指示模型肯定回『幫你寄信』");
  assert.ok(!prompt.includes("幫你簽到"), "不可指示模型肯定回『幫你簽到』");
  assert.ok(!prompt.includes("幫你買好了"), "不可指示模型肯定回『幫你買好了』");
  // 應改為：溫暖接住心意、不假裝完成、也不冷冰冰拒絕。
  assert.ok(
    prompt.includes("不要假裝你已經幫他完成了"),
    "應指示不要假裝已完成動作",
  );
  assert.ok(
    prompt.includes("也不要冷冰冰地拒絕說「我做不到」"),
    "不應冷冰冰拒絕",
  );
});

test("G2：健康為照護提醒非醫療診斷，但高風險仍明確引導求助", () => {
  const prompt = buildCompanionChatInstructions("小白", "", {});
  assert.ok(prompt.includes("不是醫療診斷"), "需聲明照護提醒非醫療診斷");
  assert.ok(
    prompt.includes("不要給診斷、不要開處方、不要講藥物劑量"),
    "需禁止診斷/處方/劑量",
  );
  assert.ok(
    prompt.includes("胸痛、呼吸困難、跌倒、嚴重不適或自傷意念"),
    "需涵蓋高風險情境",
  );
  assert.ok(
    prompt.includes("立即聯絡照護人員或尋求醫療協助"),
    "高風險需明確引導立即求助",
  );
  assert.ok(
    prompt.includes("不可因為語氣溫柔就淡化緊急程度"),
    "溫柔語氣不可降低 urgent",
  );
});

test("G3：無記憶時不捏造、不假裝『我記得』", () => {
  const prompt = buildCompanionChatInstructions("小白", "", {});
  assert.ok(
    prompt.includes("不要捏造長者的家人、喜好或病史"),
    "無記憶時不可捏造家人/喜好/病史",
  );
  assert.ok(
    prompt.includes("也不要說「我記得」假裝知道不存在的事"),
    "無記憶時不可說『我記得』",
  );
  // 無 memoryBlock 時，組裝結果不應夾帶任何具體記憶摘要區塊。
  assert.ok(
    !prompt.includes("以下是你自然記得的使用者近況"),
    "無記憶時不應出現記憶摘要區塊",
  );
});

test("G3：有記憶時夾帶記憶區塊，並維持不要說「根據紀錄」", () => {
  const memoryBlock = buildMemoryBlock("喜歡散步、女兒住台中");
  const prompt = buildCompanionChatInstructions("小白", memoryBlock, {});
  assert.ok(
    prompt.includes("以下是你自然記得的使用者近況"),
    "有記憶時應夾帶記憶區塊",
  );
  assert.ok(prompt.includes("喜歡散步、女兒住台中"), "應保留傳入的記憶摘要");
  assert.ok(
    prompt.includes("不要說「根據紀錄」"),
    "有記憶時引用仍不可說『根據紀錄』",
  );
});

test("CR-0080：即時資訊問題不可冷冰冰拒絕『不能馬上查』，且不可編造假資訊", () => {
  const prompt = buildCompanionChatInstructions("小白", "", {});
  assert.ok(prompt.includes("【即時資訊】"), "persona 應含即時資訊段落");
  assert.ok(
    prompt.includes("絕對不要冷冰冰地丟一句「我不能馬上查」"),
    "不可直接回『我不能馬上查』",
  );
  assert.ok(
    prompt.includes("幫我查"),
    "應引導長者用語音說『幫我查○○』走真正的搜尋",
  );
  assert.ok(
    prompt.includes("絕對不要編造任何天氣、日期、金額、新聞或補助細節"),
    "沒查到時不可編造假的即時資訊",
  );
});

test("台語：replyLanguage=taigi 時夾帶台語輸出語言指示", () => {
  const prompt = buildCompanionChatInstructions("小白", "", {
    replyLanguage: "taigi",
  });
  assert.ok(
    prompt.includes("你必須整段使用台語（Taiwanese Hokkien）回覆"),
    "台語提示時需輸出台語指示（證明 outputLanguageInstruction 已串接）",
  );
});

test("國語預設：無台語線索時不強制台語", () => {
  const prompt = buildCompanionChatInstructions("小白", "", {});
  assert.ok(
    prompt.includes("你必須整段使用繁體中文"),
    "預設需輸出繁體中文指示",
  );
  assert.ok(
    !prompt.includes("你必須整段使用台語（Taiwanese Hokkien）回覆"),
    "無台語線索時不應強制台語",
  );
});
