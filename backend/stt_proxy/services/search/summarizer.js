const OpenAI = require("openai");

let client;

function getClient() {
  if (!client) client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  return client;
}

function toSources(results) {
  return (results || [])
    .filter((item) => item.url)
    .slice(0, 4)
    .map((item) => ({
      title: item.title || "來源資料",
      url: item.url,
      domain: item.domain || siteNameFromUrl(item.url || ""),
      siteName: item.siteName || item.site_name || item.domain || "",
      publishedAt: item.publishedAt || item.published_at || null,
      summary: item.summary || item.snippet || item.content || "",
    }));
}

function siteNameFromUrl(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch (_) {
    return "";
  }
}

function fallbackSummary({ query, results, mode }) {
  const sources = toSources(results);
  if (!sources.length) {
    return {
      answer: "目前沒有取得可靠來源，我先不亂說，我可以先陪你聊聊或稍後再幫你查。",
      summary: "沒有可靠來源。",
      sources,
    };
  }
  const first = results[0];
  const base = first.summary || first.snippet || first.content || "";
  const safety =
    mode === "health_tip"
      ? "這只是一般衛教提醒，不能代替醫師診斷；如果有嚴重不舒服，要請家人陪你問醫師。"
      : "";
  const answer = limitSentences(
    `我幫你整理一下喔。${base.slice(0, 120)} ${safety}`.trim(),
  );
  return {
    answer,
    summary: base.slice(0, 80) || query,
    sources,
  };
}

async function summarizeWithAi({ query, mode, results, webAnswer = "" }) {
  const sources = toSources(results);
  if (!sources.length && !webAnswer) {
    return fallbackSummary({ query, results, mode });
  }
  if (!process.env.OPENAI_API_KEY) {
    return fallbackSummary({ query, results, mode });
  }

  try {
    const response = await getClient().chat.completions.create({
      model: process.env.SEARCH_SUMMARY_MODEL || process.env.MEMORY_MODEL || "gpt-4o-mini",
      temperature: 0.25,
      messages: [
        {
          role: "system",
          content:
            "你是一隻陪伴長者的 AI 寵物。使用繁體中文，3 到 5 句，溫柔、白話、像陪伴者。健康資訊不能診斷，嚴重症狀提醒詢問醫師。一定根據提供來源，不要捏造來源或事實。",
        },
        {
          role: "user",
          content: JSON.stringify({
            query,
            mode,
            webAnswer,
            sources,
            excerpts: (results || []).slice(0, 4).map((item) => ({
              title: item.title,
              siteName: item.siteName,
              summary: item.summary || item.snippet || "",
              content: (item.content || "").slice(0, 700),
            })),
          }),
        },
      ],
    });
    const answer = limitSentences(
      (response.choices?.[0]?.message?.content || "").trim(),
    );
    return {
      answer: answer || fallbackSummary({ query, results, mode }).answer,
      summary: (results?.[0]?.summary || answer || query).slice(0, 120),
      sources,
    };
  } catch (error) {
    console.error("[search-summary] AI summary failed", error?.message || error);
    return fallbackSummary({ query, results, mode });
  }
}

function limitSentences(text, maxSentences = 5) {
  const normalized = (text || "").replace(/\s+/g, " ").trim();
  if (!normalized) return "";
  const parts = normalized.match(/[^。！？!?]+[。！？!?]?/g) || [normalized];
  return parts.slice(0, maxSentences).join("").trim();
}

module.exports = {
  summarizeWithAi,
  fallbackSummary,
  toSources,
  limitSentences,
};
