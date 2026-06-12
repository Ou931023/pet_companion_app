const OpenAI = require("openai");

let client;

function getOpenAIClient() {
  if (!client) {
    client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });
  }
  return client;
}

// CR-0080：即時資訊 intent 關鍵字。前端 web_search_service.dart 的 shouldSearch
// 必須與這份清單保持一致（兩端對齊，避免前端放行但後端拒收、回出生硬的「查不到」）。
// 只放「明確需要外部即時資訊」的詞；刻意不放會誤判一般陪伴聊天的單字（例如單獨的
// 「今天」「現在」「最近」），以免把「我今天有點累」這類心情話誤導進搜尋。
const REALTIME_INFO_KEYWORDS = [
  // 新聞 / 防詐
  "今天有什麼新聞",
  "新聞",
  "最新消息",
  "防詐",
  "詐騙新聞",
  "最近詐騙",
  // 天氣
  "查天氣",
  "天氣",
  "氣溫",
  "會不會下雨",
  "下雨機率",
  // 活動
  "附近有什麼活動",
  "附近活動",
  "最近活動",
  // 主動查詢動詞
  "幫我查",
  "查一下",
  "幫我搜尋",
  "幫我搜",
  "上網查",
  "搜尋",
  "即時資訊",
  "健康資訊",
  // 補助 / 政策
  "補助",
  "津貼",
  "長照",
  "政策",
  "法規",
  "規定",
  // 價格 / 時刻
  "油價",
  "匯率",
  "股市",
  "股價",
  "票價",
  "高鐵時刻",
  "台鐵時刻",
  "營業時間",
  "開放時間",
  // 災防 / 公共
  "颱風",
  "地震",
  "路況",
  "停水",
  "停電",
  "確診",
  "疫情",
  // 申請流程
  "怎麼申請",
  "如何申請",
];

function needsWebSearch(text) {
  const normalized = (text || "").trim();
  if (!normalized) return false;
  return REALTIME_INFO_KEYWORDS.some((keyword) => normalized.includes(keyword));
}

function isHighRiskQuery(text) {
  const normalized = (text || "").trim();
  return [
    "健康",
    "醫療",
    "藥",
    "症狀",
    "疼痛",
    "血壓",
    "法律",
    "合約",
    "告",
    "投資",
    "股票",
    "基金",
    "保險",
    "貸款",
  ].some((keyword) => normalized.includes(keyword));
}

function inferTopic(text) {
  if ((text || "").includes("新聞") || (text || "").includes("詐騙")) {
    return "news";
  }
  if ((text || "").includes("股票") || (text || "").includes("投資")) {
    return "finance";
  }
  return "general";
}

function isWeatherQuery(text) {
  return (text || "").includes("天氣") || (text || "").includes("氣溫");
}

function extractWeatherLocation(text) {
  const normalized = (text || "").replace(/[，。！？!?]/g, " ").trim();
  const match = normalized.match(/(?:幫我查|查一下|查|看一下|上網查)?\s*([\u4e00-\u9fa5A-Za-z\s]{2,20}?)(?:今天|明天|現在|目前)?(?:的)?(?:天氣|氣溫)/);
  const location = (match?.[1] || "")
    .replace(/今天|明天|現在|目前|上網|幫我|查一下|查|看一下/g, "")
    .trim();
  return location || process.env.DEFAULT_WEATHER_LOCATION || "嘉義市";
}

function weatherCodeDescription(code) {
  if (code === 0) return "晴朗";
  if ([1, 2, 3].includes(code)) return "多雲";
  if ([45, 48].includes(code)) return "有霧";
  if ([51, 53, 55, 56, 57].includes(code)) return "毛毛雨";
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return "下雨";
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "下雪";
  if ([95, 96, 99].includes(code)) return "雷雨";
  return "天氣狀況不明";
}

async function fetchJsonWithTimeout(url, timeoutMs = 8000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(data?.reason || data?.message || "Weather request failed");
      error.status = response.status;
      throw error;
    }
    return data;
  } catch (error) {
    if (error?.name === "AbortError") {
      const timeoutError = new Error("Weather request timeout");
      timeoutError.code = "NETWORK_ERROR";
      throw timeoutError;
    }
    if (
      error?.code === "ENOTFOUND" ||
      error?.code === "ECONNRESET" ||
      error?.code === "ETIMEDOUT" ||
      error?.code === "NETWORK_ERROR"
    ) {
      error.code = "NETWORK_ERROR";
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function searchWeather(query) {
  const location = extractWeatherLocation(query);
  const geocodeUrl = new URL("https://geocoding-api.open-meteo.com/v1/search");
  geocodeUrl.searchParams.set("name", location);
  geocodeUrl.searchParams.set("count", "1");
  geocodeUrl.searchParams.set("language", "zh");
  geocodeUrl.searchParams.set("format", "json");

  const geocode = await fetchJsonWithTimeout(geocodeUrl);
  const place = geocode?.results?.[0];
  if (!place) {
    return {
      answer: `我目前查不到「${location}」的天氣，可以再說一次城市或地區嗎？`,
      sources: [],
      highRisk: false,
    };
  }

  const weatherUrl = new URL("https://api.open-meteo.com/v1/forecast");
  weatherUrl.searchParams.set("latitude", place.latitude);
  weatherUrl.searchParams.set("longitude", place.longitude);
  weatherUrl.searchParams.set("current", "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m");
  weatherUrl.searchParams.set("daily", "temperature_2m_max,temperature_2m_min,precipitation_probability_max");
  weatherUrl.searchParams.set("forecast_days", "1");
  weatherUrl.searchParams.set("timezone", "auto");

  const weather = await fetchJsonWithTimeout(weatherUrl);
  const current = weather.current || {};
  const daily = weather.daily || {};
  const adminName = (place.admin1 || "").toString().split(" or ")[0].trim();
  const placeName = [place.name, adminName].filter(Boolean).join("，");
  const description = weatherCodeDescription(Number(current.weather_code));
  const temperature = Math.round(Number(current.temperature_2m));
  const max = Math.round(Number(daily.temperature_2m_max?.[0]));
  const min = Math.round(Number(daily.temperature_2m_min?.[0]));
  const rain = Math.round(Number(daily.precipitation_probability_max?.[0] || 0));
  const wind = Math.round(Number(current.wind_speed_10m || 0));

  return {
    answer: `${placeName || location}目前約 ${temperature} 度，天氣${description}，今天高溫約 ${max} 度、低溫約 ${min} 度，降雨機率約 ${rain}%。出門可以留意補水，風速約每小時 ${wind} 公里。`,
    sources: [
      {
        index: 1,
        title: "Open-Meteo Weather Forecast API",
        url: "https://open-meteo.com/",
        content: "Current weather and daily forecast from Open-Meteo.",
      },
    ],
    highRisk: false,
  };
}

async function searchWithTavily(query) {
  const apiKey = process.env.TAVILY_API_KEY;
  if (!apiKey) {
    const error = new Error("Missing TAVILY_API_KEY");
    error.code = "MISSING_TAVILY_API_KEY";
    throw error;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch("https://api.tavily.com/search", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        query,
        topic: inferTopic(query),
        search_depth: "basic",
        include_answer: "basic",
        include_raw_content: false,
        max_results: 5,
      }),
      signal: controller.signal,
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(data?.error || data?.message || "Tavily search failed");
      error.status = response.status;
      throw error;
    }
    return data;
  } catch (error) {
    if (error?.name === "AbortError") {
      const timeoutError = new Error("Tavily search timeout");
      timeoutError.code = "NETWORK_ERROR";
      throw timeoutError;
    }
    if (
      error?.code === "ENOTFOUND" ||
      error?.code === "ECONNRESET" ||
      error?.code === "ETIMEDOUT" ||
      error?.code === "NETWORK_ERROR"
    ) {
      error.code = "NETWORK_ERROR";
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function summarizeForElderly({ query, tavilyData }) {
  const highRisk = isHighRiskQuery(query);
  const sources = (tavilyData.results || [])
    .slice(0, 4)
    .map((result, index) => ({
      index: index + 1,
      title: result.title || "",
      url: result.url || "",
      content: (result.content || "").toString().slice(0, 500),
    }));

  if (!process.env.OPENAI_API_KEY) {
    const fallback = tavilyData.answer || sources.map((s) => s.content).filter(Boolean).join(" ");
    return {
      answer: trimAnswer(fallback, highRisk),
      sources,
      highRisk,
    };
  }

  const response = await getOpenAIClient().chat.completions.create({
    model: process.env.WEB_SEARCH_SUMMARY_MODEL || process.env.MEMORY_MODEL || "gpt-4o-mini",
    temperature: 0.3,
    messages: [
      {
        role: "system",
        content:
          "你是一隻陪伴長者的 AI 寵物。請把搜尋結果整理成繁體中文，2 到 4 句，白話、溫柔、不要嚇人。不要逐字貼來源。醫療、法律、金融問題要提醒仍需詢問專業人員。",
      },
      {
        role: "user",
        content: JSON.stringify({
          query,
          tavilyAnswer: tavilyData.answer || "",
          highRisk,
          sources,
        }),
      },
    ],
  });

  return {
    answer: trimAnswer(response.choices?.[0]?.message?.content || tavilyData.answer || "", highRisk),
    sources,
    highRisk,
  };
}

function trimAnswer(text, highRisk) {
  const normalized = (text || "").replace(/\s+/g, " ").trim();
  const base = normalized.length > 220 ? `${normalized.slice(0, 220)}...` : normalized;
  if (!highRisk) return base || "我查到的資料不多，晚點再幫你確認一次。";
  if (base.includes("專業")) return base;
  return `${base || "我查到的資料不多。"} 這類事情還是要再問醫師、律師或專業人員，比較安心。`;
}

async function searchAndSummarize(query) {
  if (isWeatherQuery(query)) {
    return searchWeather(query);
  }
  const tavilyData = await searchWithTavily(query);
  return summarizeForElderly({ query, tavilyData });
}

module.exports = {
  needsWebSearch,
  isHighRiskQuery,
  isWeatherQuery,
  extractWeatherLocation,
  searchAndSummarize,
};
