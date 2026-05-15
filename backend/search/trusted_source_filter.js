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

function isTrustedSource(source = {}) {
  const domain = source.domain || domainFromUrl(source.url || "");
  if (TRUSTED_SOURCE_TYPES.has(source.sourceType || source.source_type)) return true;
  return isTrustedDomain(domain);
}

function filterTrustedSources(sources = []) {
  return (sources || [])
    .map((source) => ({
      ...source,
      domain: source.domain || domainFromUrl(source.url || ""),
    }))
    .filter(isTrustedSource);
}

module.exports = {
  TRUSTED_DOMAINS,
  TRUSTED_SOURCE_TYPES,
  domainFromUrl,
  isTrustedSource,
  filterTrustedSources,
};
