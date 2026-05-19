function buildIntentDraft({ userText = "", petName = "陪伴寶" } = {}) {
  const text = userText.toString().trim();
  if (!text) return null;

  if (/(播放|放|聽).*(音樂|歌|老歌|放鬆|白噪音)|音樂/.test(text)) {
    return {
      toolName: "play_music",
      arguments: { query: extractMusicQuery(text) },
      userFacingMessage: "我可以幫你打開音樂搜尋。",
    };
  }
  if (/(打給|撥給|打電話|撥電話|聯絡).*(女兒|兒子|家人|太太|先生|醫生|護理師|媽媽|爸爸)|幫我打給/.test(text)) {
    return {
      toolName: "open_phone_dialer",
      arguments: { contactName: extractContactName(text) },
      userFacingMessage: "要幫你開啟撥號畫面嗎？不會自動撥出。",
    };
  }
  if (/(寄|寫|發).*(email|Email|信|郵件)|email 給|Email 給/.test(text)) {
    return {
      toolName: "create_email_draft",
      arguments: {
        to: extractEmailRecipient(text),
        subject: "來自陪伴 App 的訊息",
        body: extractEmailBody(text),
      },
      userFacingMessage: "要幫你建立 Email 草稿嗎？不會自動寄出。",
    };
  }
  if (/(提醒我|記得提醒|幫我提醒|提醒).*(吃藥|喝水|回診|散步|睡覺|量血壓|量血糖|晚上|早上|下午|點|時)/.test(text)) {
    return {
      toolName: "create_reminder",
      arguments: { text },
      userFacingMessage: "要幫你建立這個提醒嗎？",
    };
  }
  if (/(查|搜尋|查一下|幫我查|新聞|最新|防詐|詐騙|健康小知識)/.test(text)) {
    return {
      toolName: "search_trusted_info",
      arguments: { query: text },
      userFacingMessage: "我可以幫你查可信資訊。",
    };
  }
  if (/(去|打開|開啟|帶我去).*(商城|商店|提醒|設定|紀錄|首頁|記憶)/.test(text)) {
    return {
      toolName: "open_app_route",
      arguments: { route: extractAppRoute(text) },
      userFacingMessage: "我可以幫你切到 App 裡的頁面。",
    };
  }
  if (/(記住|幫我記得|你要記得|我喜歡|我不喜歡)/.test(text)) {
    return {
      toolName: "save_memory",
      arguments: { memoryText: text },
      userFacingMessage: `${petName} 可以幫你記住這件事，要保存嗎？`,
    };
  }
  if (/(我之前|你記得|查一下我|我的記憶|我喜歡什麼)/.test(text)) {
    return {
      toolName: "retrieve_memory",
      arguments: { query: text },
      userFacingMessage: "我可以幫你找找之前記住的內容。",
    };
  }
  return null;
}

function extractMusicQuery(text) {
  if (/台語老歌/.test(text)) return "台語老歌 放鬆";
  if (/放鬆/.test(text)) return "放鬆音樂";
  if (/白噪音/.test(text)) return "白噪音";
  return text.replace(/幫我|播放|放|聽|音樂/g, "").trim() || "放鬆音樂";
}

function extractContactName(text) {
  const contacts = ["女兒", "兒子", "家人", "太太", "先生", "醫生", "護理師", "媽媽", "爸爸"];
  return contacts.find((name) => text.includes(name)) || "";
}

function extractEmailRecipient(text) {
  const recipients = ["家人", "女兒", "兒子", "太太", "先生", "醫生"];
  return recipients.find((name) => text.includes(name)) || "";
}

function extractEmailBody(text) {
  const match = text.match(/說(.+)$/);
  return (match?.[1] || text).trim();
}

function extractAppRoute(text) {
  if (/商城|商店/.test(text)) return "/shop";
  if (/提醒/.test(text)) return "/reminders";
  if (/設定/.test(text)) return "/settings";
  if (/紀錄|歷史/.test(text)) return "/history";
  if (/記憶/.test(text)) return "/memories";
  return "/home";
}

module.exports = {
  buildIntentDraft,
};
