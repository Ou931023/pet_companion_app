const axios = require("axios");
const cheerio = require("cheerio");
const { upsertDocument } = require("./documentStore");

const defaultAllowedDomains = [
  "www.hpa.gov.tw",
  "hpa.gov.tw",
  "www.mohw.gov.tw",
  "mohw.gov.tw",
  "www.cdc.gov.tw",
  "cdc.gov.tw",
  "www.nhi.gov.tw",
  "nhi.gov.tw",
];

const robotsCache = new Map();
const lastRequestByDomain = new Map();
const minDelayMs = Number(process.env.CRAWLER_MIN_DELAY_MS || 2500);

function allowedDomains() {
  const extra = (process.env.CRAWLER_ALLOWED_DOMAINS || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return [...new Set([...defaultAllowedDomains, ...extra])];
}

function allowedUrls() {
  return (process.env.CRAWLER_ALLOWED_URLS || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function isAllowedUrl(urlText) {
  let url;
  try {
    url = new URL(urlText);
  } catch (_) {
    return false;
  }
  if (!["http:", "https:"].includes(url.protocol)) return false;
  const explicit = allowedUrls();
  if (explicit.length && explicit.includes(url.href)) return true;
  return allowedDomains().includes(url.hostname);
}

async function waitForDomain(domain) {
  const last = lastRequestByDomain.get(domain) || 0;
  const elapsed = Date.now() - last;
  if (elapsed < minDelayMs) {
    await new Promise((resolve) => setTimeout(resolve, minDelayMs - elapsed));
  }
  lastRequestByDomain.set(domain, Date.now());
}

async function robotsAllowed(urlText) {
  const url = new URL(urlText);
  const robotsUrl = `${url.origin}/robots.txt`;
  if (!robotsCache.has(url.origin)) {
    try {
      const response = await axios.get(robotsUrl, { timeout: 5000, responseType: "text" });
      robotsCache.set(url.origin, response.data || "");
    } catch (error) {
      console.warn("[crawler] robots.txt unavailable, skipping crawl for safety", {
        robotsUrl,
        error: error?.message || error,
      });
      robotsCache.set(url.origin, null);
    }
  }
  const rules = robotsCache.get(url.origin);
  if (rules === null) return false;
  const path = url.pathname || "/";
  const lines = rules.split(/\r?\n/).map((line) => line.trim());
  let appliesToAll = false;
  for (const line of lines) {
    if (!line || line.startsWith("#")) continue;
    const [rawKey, ...rest] = line.split(":");
    const key = rawKey.trim().toLowerCase();
    const value = rest.join(":").trim();
    if (key === "user-agent") appliesToAll = value === "*";
    if (appliesToAll && key === "disallow" && value && path.startsWith(value)) {
      return false;
    }
  }
  return true;
}

function cleanText(text) {
  return (text || "").replace(/\s+/g, " ").trim();
}

function parseHtml({ html, url }) {
  const $ = cheerio.load(html);
  $("script, style, nav, footer, header, aside, form, noscript, svg").remove();
  const title =
    cleanText($("meta[property='og:title']").attr("content")) ||
    cleanText($("title").first().text()) ||
    cleanText($("h1").first().text()) ||
    "未命名文章";
  const publishedAt =
    cleanText($("meta[property='article:published_time']").attr("content")) ||
    cleanText($("time[datetime]").first().attr("datetime")) ||
    cleanText($("time").first().text()) ||
    null;
  const mainText = cleanText(
    $("article").text() || $("main").text() || $("body").text(),
  );
  const content = mainText.slice(0, 6000);
  const parsedUrl = new URL(url);
  return {
    title,
    url,
    siteName:
      cleanText($("meta[property='og:site_name']").attr("content")) ||
      parsedUrl.hostname.replace(/^www\./, ""),
    domain: parsedUrl.hostname,
    publishedAt,
    crawledAt: new Date().toISOString(),
    content,
    summary: content.slice(0, 180),
    category: "health_tip",
    sourceType: "trusted_crawl",
    isActive: content.length > 80,
  };
}

async function crawlOne(url) {
  if (!isAllowedUrl(url)) {
    return { url, ok: false, error: "URL is not in crawler whitelist" };
  }
  const parsed = new URL(url);
  try {
    const allowed = await robotsAllowed(url);
    if (!allowed) return { url, ok: false, error: "Blocked by robots.txt" };
    await waitForDomain(parsed.hostname);
    const response = await axios.get(url, {
      timeout: 10000,
      responseType: "text",
      headers: {
        "User-Agent": "PetCompanionDemoCrawler/1.0 (+local graduation project)",
      },
      maxRedirects: 3,
    });
    const document = parseHtml({ html: response.data, url });
    const saved = await upsertDocument(document);
    return { url, ok: true, document: saved };
  } catch (error) {
    console.error("[crawler] crawl failed", { url, error: error?.message || error });
    return { url, ok: false, error: error?.message || "crawl failed" };
  }
}

async function refreshCrawler({ urls = [] }) {
  const safeUrls = urls.slice(0, Number(process.env.CRAWLER_MAX_URLS_PER_REFRESH || 3));
  const results = [];
  for (const url of safeUrls) {
    results.push(await crawlOne(url));
  }
  return {
    success: results.some((item) => item.ok),
    allowedDomains: allowedDomains(),
    results,
  };
}

module.exports = {
  refreshCrawler,
  isAllowedUrl,
};
