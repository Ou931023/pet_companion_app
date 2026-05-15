const { domainFromUrl } = require("./trusted_source_filter");

function compact(text = "", maxLength = 120) {
  const normalized = text.toString().replace(/\s+/g, " ").trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, maxLength - 1)}…`;
}

function formatSource(source = {}) {
  const url = (source.url || "").toString();
  const domain = (source.domain || domainFromUrl(url)).toString();
  return {
    title: (source.title || "可信資料來源").toString(),
    url,
    domain,
    siteName: (source.siteName || source.site_name || domain || "可信來源").toString(),
    publishedAt: source.publishedAt || source.published_at || null,
    summary: compact(source.summary || source.snippet || source.content || "", 140),
  };
}

function formatSources(sources = []) {
  return (sources || []).filter((source) => source?.url).slice(0, 4).map(formatSource);
}

module.exports = {
  compact,
  formatSource,
  formatSources,
};
