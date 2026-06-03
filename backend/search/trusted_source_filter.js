// 搜尋來源過濾（政策：盡量不限制）。
//
// 依產品決策（2026-06-03）：一般網路來源「全部放行」，只阻擋限制級 / 成人內容。
// 不再用白名單把主流新聞（reuters / nbcnews / 中央社 / udn…）擋掉，讓「找新聞」能回真實結果。
// 仍保留 TRUSTED_DOMAINS / isTrustedSource 供其他模組標記「特別可信」之用（非過濾門檻）。

// 仍標記為「特別可信」的官方 / 醫療 / 公共來源（僅供標記，非過濾條件）。
const TRUSTED_DOMAINS = [
  ".gov.tw",
  ".edu.tw",
  ".edu",
  "who.int",
  "cdc.gov",
  "nih.gov",
  "mayoclinic.org",
  "nhs.uk",
  "health99.hpa.gov.tw",
  "hpa.gov.tw",
  "mohw.gov.tw",
  "police.gov.tw",
  "165.npa.gov.tw",
  "ey.gov.tw",
  "gov.tw",
  "cna.com.tw",
  "pts.org.tw",
  "rti.org.tw",
];

const TRUSTED_SOURCE_TYPES = new Set([
  "mock_trusted",
  "trusted_crawl",
  "government",
  "hospital",
  "university",
  "public_health",
  "trusted_news",
  "official_long_term_care",
]);

// 限制級 / 成人內容阻擋清單（唯一的過濾條件）。網域比對 + 標題/網址關鍵字。
const ADULT_DOMAINS = [
  "pornhub.com",
  "xvideos.com",
  "xnxx.com",
  "xhamster.com",
  "redtube.com",
  "youporn.com",
  "onlyfans.com",
  "brazzers.com",
  "chaturbate.com",
  "stripchat.com",
  "livejasmin.com",
  "spankbang.com",
  "eporner.com",
  "porn.com",
  "adultfriendfinder.com",
];

// 出現在網址 / 標題即視為成人內容（保守、避免誤殺一般醫療衛教用語）。
const ADULT_KEYWORDS = [
  "porn",
  "xxx",
  "sexcam",
  "camgirl",
  "escort",
  "成人影片",
  "色情",
  "情色",
  "av女優",
  "做愛影片",
];

function domainFromUrl(url = "") {
  try {
    return new URL(url).hostname.toLowerCase().replace(/^www\./, "");
  } catch (_) {
    return "";
  }
}

function isTrustedDomain(domain = "") {
  const normalized = domain.toLowerCase().replace(/^www\./, "");
  return TRUSTED_DOMAINS.some((trusted) => {
    if (trusted.startsWith(".")) return normalized.endsWith(trusted);
    return normalized === trusted || normalized.endsWith(`.${trusted}`);
  });
}

// 「特別可信」標記（非過濾條件）。
function isTrustedSource(source = {}) {
  const domain = source.domain || domainFromUrl(source.url || "");
  if (TRUSTED_SOURCE_TYPES.has(source.sourceType || source.source_type)) return true;
  return isTrustedDomain(domain);
}

// 限制級 / 成人內容判定（唯一阻擋條件）。
function isAdultSource(source = {}) {
  const domain = (source.domain || domainFromUrl(source.url || "")).toLowerCase();
  if (ADULT_DOMAINS.some((d) => domain === d || domain.endsWith(`.${d}`))) {
    return true;
  }
  const haystack = `${source.url || ""} ${source.title || ""} ${source.snippet || ""}`
    .toLowerCase();
  return ADULT_KEYWORDS.some((kw) => haystack.includes(kw.toLowerCase()));
}

// 過濾來源：政策為「全部放行，只擋成人內容」。
function filterTrustedSources(sources = []) {
  return (sources || [])
    .map((source) => ({
      ...source,
      domain: source.domain || domainFromUrl(source.url || ""),
    }))
    .filter((source) => !isAdultSource(source));
}

module.exports = {
  TRUSTED_DOMAINS,
  TRUSTED_SOURCE_TYPES,
  ADULT_DOMAINS,
  ADULT_KEYWORDS,
  domainFromUrl,
  isTrustedDomain,
  isTrustedSource,
  isAdultSource,
  filterTrustedSources,
};
