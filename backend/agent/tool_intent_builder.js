// 統一 Agent Intent 判斷（regex 規則式，deterministic，方便單元測試）。
//
// 偵測順序：高影響 / 語義明確的意圖先判，避免被廣義規則（如 navigate / save_memory）吃掉。
// 每個意圖回傳 { toolName, arguments, userFacingMessage }；高影響操作的最終確認文字
// 由 tool_policy 的 defaultUserFacingMessage 統一把關（這裡給的是友善起手語）。
function buildIntentDraft({ userText = "", petName = "陪伴寶" } = {}) {
  const text = userText.toString().trim();
  if (!text) return null;

  // 1) 登出（高影響：改變身分狀態）
  if (/登出|登出帳號|我要登出|幫我登出|幫我登出帳號/.test(text)) {
    return {
      toolName: "logout",
      arguments: {},
      userFacingMessage: "要幫你登出嗎？",
    };
  }

  // 2) 刪除記憶（高影響：不可逆）
  if (/(刪|刪除|刪掉|清除|移除).{0,6}(記憶|記得|我說的|那件事)|忘記我(剛|剛剛|之前|說|提)/.test(text)) {
    return {
      toolName: "delete_memory",
      arguments: { target: text },
      userFacingMessage: "要刪掉這個記憶嗎？刪掉就找不回來囉。",
    };
  }

  // 3) 購買寵物造型（高影響：花錢）
  if (/(買|購買|入手|想要|換).{0,6}(外觀|造型|皮膚|樣子|新衣|新造型|寵物造型)|購買寵物/.test(text)) {
    return {
      toolName: "purchase_pet_skin",
      arguments: { skinName: extractSkinName(text) },
      userFacingMessage: "要購買這個寵物造型嗎？",
    };
  }

  // 4) 通知照護人員（高影響：對外通知；用「通知 / 告知 / 讓…知道」與打電話區分）
  if (/(通知|告知|告訴|讓).{0,6}(照護員|照服員|護理師|家屬|家人).{0,4}(知道|一下|我的?狀況)?|通知照護|聯絡.{0,2}照護.{0,2}(來|過來)/.test(text)) {
    return {
      toolName: "notify_caregiver",
      arguments: { reason: text },
      userFacingMessage: "要我通知照護人員嗎？",
    };
  }

  // 5) 打電話（make_call，高影響：對外）
  if (/(打給|撥給|打電話|撥電話|打.{0,2}電話|撥.{0,2}電話)|(聯絡|連絡).{0,4}(女兒|兒子|家人|太太|先生|醫生|護理師|照護員|媽媽|爸爸|阿姨)/.test(text)) {
    return {
      toolName: "open_phone_dialer",
      arguments: { contactName: extractContactName(text) },
      userFacingMessage: "要幫你開啟撥號畫面嗎？不會自動撥出。",
    };
  }

  // 6) 傳訊息（send_message，高影響：對外）；需要抽 recipient 與 body
  if (/(傳|發|捎).{0,3}(訊息|簡訊|信)|幫我(跟|向|和|對)\S{1,6}說|(跟|向|和|對)\S{1,6}說(一聲|一下)?/.test(text)) {
    const recipient = extractMessageRecipient(text);
    return {
      toolName: "send_message",
      arguments: {
        recipient,
        contactName: recipient,
        body: extractMessageBody(text),
      },
      userFacingMessage: "要幫你傳這則訊息嗎？傳出前你再確認一次內容。",
    };
  }

  // 7) Email 草稿（既有）
  if (/(寄|寫|發).{0,3}(email|Email|信|郵件)|email 給|Email 給/.test(text)) {
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

  // 8) 播放音樂（低風險直接做）
  if (/(播放|放|聽).{0,3}(音樂|歌|老歌|放鬆|白噪音)|音樂|想聽.{0,3}歌/.test(text)) {
    return {
      toolName: "play_music",
      arguments: { query: extractMusicQuery(text) },
      userFacingMessage: "好的，幫你播放音樂。",
    };
  }

  // 9) 建立提醒（低風險直接做）
  if (/(提醒我|記得提醒|幫我提醒|提醒).{0,8}(吃藥|喝水|回診|散步|睡覺|量血壓|量血糖|運動|起床|晚上|早上|下午|中午|睡前|點|時)/.test(text)) {
    return {
      toolName: "create_reminder",
      arguments: { text },
      userFacingMessage: "好，我幫你記下這個提醒。",
    };
  }

  // 10) 說故事（低風險直接做）
  if (/(說|講|來|聽).{0,3}(故事|笑話)|說.{0,2}故事|講.{0,2}故事/.test(text)) {
    return {
      toolName: "tell_story",
      arguments: { topic: extractStoryTopic(text) },
      userFacingMessage: "好，我說一個故事給你聽。",
    };
  }

  // 11) 查可信資訊（低風險直接做）
  if (/(查|搜尋|查一下|幫我查|新聞|最新|防詐|詐騙|健康小知識)/.test(text)) {
    return {
      toolName: "search_trusted_info",
      arguments: { query: text },
      userFacingMessage: "我幫你查可信資訊。",
    };
  }

  // 12) 前往 App 頁面（navigate，低風險直接做）
  if (/(去|打開|開啟|帶我去|到|逛|我要看|我要去|切到).{0,4}(商城|商店|商場|商场|店裡|店里|提醒|設定|设定|紀錄|纪录|歷史|历史|首頁|首页|記憶|记忆|遊戲|游戏|玩遊戲|換寵物|换宠物|寵物造型)/.test(text)) {
    return {
      toolName: "open_app_route",
      arguments: { route: extractAppRoute(text) },
      userFacingMessage: resolveNavigateMessage(extractAppRoute(text)),
    };
  }

  // 13) 記住這件事（save_memory，低風險直接做，但要讓使用者知道已記住）
  if (/(記住|幫我記得|你要記得|我喜歡|我不喜歡|幫我記住)/.test(text)) {
    return {
      toolName: "save_memory",
      arguments: { memoryText: text },
      userFacingMessage: `好，${petName}幫你記住了。`,
    };
  }

  // 14) 查詢長期記憶（recall_memory，低風險直接做）
  if (/(我之前|你記得|查一下我|我的記憶|我喜歡什麼|你還記得)/.test(text)) {
    return {
      toolName: "retrieve_memory",
      arguments: { query: text },
      userFacingMessage: "我找找之前記住的內容。",
    };
  }
  return null;
}

function extractMusicQuery(text) {
  if (/台語老歌/.test(text)) return "台語老歌 放鬆";
  if (/老歌/.test(text)) return "懷舊老歌";
  if (/放鬆/.test(text)) return "放鬆音樂";
  if (/白噪音/.test(text)) return "白噪音";
  return text.replace(/幫我|播放|放|聽|音樂|我想/g, "").trim() || "放鬆音樂";
}

const CONTACT_NAMES = [
  "女兒",
  "兒子",
  "孫子",
  "孫女",
  "家人",
  "太太",
  "先生",
  "老伴",
  "醫生",
  "護理師",
  "照護員",
  "照服員",
  "媽媽",
  "爸爸",
  "阿姨",
  "鄰居",
];

function extractContactName(text) {
  return CONTACT_NAMES.find((name) => text.includes(name)) || "";
}

function extractMessageRecipient(text) {
  // 優先抓「跟/向/對 X 說」的 X；找不到再退回通用聯絡人字典。
  const match = text.match(/(?:跟|向|和|對|幫我跟|幫我向)\s*([一-龥A-Za-z]{1,6}?)\s*說/);
  if (match && match[1]) return match[1].trim();
  return extractContactName(text);
}

function extractMessageBody(text) {
  const match = text.match(/說(?:一聲|一下)?\s*[，,：:]?\s*(.+)$/);
  if (match && match[1]) return match[1].trim();
  return "";
}

function extractEmailRecipient(text) {
  const recipients = ["家人", "女兒", "兒子", "太太", "先生", "醫生"];
  return recipients.find((name) => text.includes(name)) || "";
}

function extractEmailBody(text) {
  const match = text.match(/說(.+)$/);
  return (match?.[1] || text).trim();
}

function extractStoryTopic(text) {
  const match = text.match(/(?:關於|講|說)\s*([一-龥A-Za-z]{1,8})\s*的?(?:故事|笑話)/);
  return (match?.[1] || "").trim();
}

function extractSkinName(text) {
  const match = text.match(/(?:買|購買|入手|換)\s*([一-龥A-Za-z]{1,8})\s*(?:外觀|造型|皮膚|樣子)/);
  return (match?.[1] || "").trim();
}

function extractAppRoute(text) {
  if (/商城|商店|商場|商场|店裡|店里|換寵物|换宠物|寵物造型/.test(text)) return "/shop";
  if (/提醒/.test(text)) return "/reminders";
  if (/設定|设定/.test(text)) return "/settings";
  if (/紀錄|纪录|歷史|历史/.test(text)) return "/history";
  if (/記憶|记忆/.test(text)) return "/memories";
  if (/遊戲|游戏|玩遊戲/.test(text)) return "/puzzle";
  return "/home";
}

function resolveNavigateMessage(route) {
  return (
    {
      "/reminders": "好，我帶你去看提醒。",
      "/settings": "好，我帶你去設定。",
      "/history": "好，我帶你去看紀錄。",
      "/memories": "好，我帶你去看記憶。",
      "/puzzle": "好，我帶你去玩遊戲。",
      "/shop": "好，我帶你去換寵物造型。",
    }[route] || "好，我帶你過去。"
  );
}

module.exports = {
  buildIntentDraft,
  // 匯出抽取函式供測試。
  extractMessageRecipient,
  extractMessageBody,
  extractAppRoute,
};
