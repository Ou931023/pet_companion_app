const { classifyQuery } = require("./queryRouter");
const { searchLocalIndex } = require("./localIndexSearchProvider");
const { searchWeb } = require("./openAiWebSearchProvider");
const mock = require("./mockSearchProvider");
const { summarizeWithAi, toSources } = require("./summarizer");
const { logSearchQuery } = require("./documentStore");
const { filterTrustedSources } = require("../../../search/trusted_source_filter");

function responseShape({
  answer,
  summary,
  sources,
  mode,
  provider,
  toolUsed,
  confidence,
  shouldShowSources,
}) {
  return {
    answer,
    summary,
    sources: sources || [],
    mode,
    provider,
    toolUsed,
    confidence,
    shouldShowSources,
  };
}

async function runWebSearch(query) {
  try {
    return await searchWeb({ query });
  } catch (error) {
    console.error("[search] web provider failed", error?.message || error);
    return null;
  }
}

async function search({ query, mode = "auto", userProfile = {} }) {
  const routed = classifyQuery(query, mode);
  const resolvedMode = routed.mode;
  const storyType = routed.storyType || "";

  if (resolvedMode === "companion_chat") {
    const result = mock.companionChat(query);
    await logSearchQuery({ userQuery: query, queryMode: resolvedMode, usedProvider: result.provider });
    return responseShape({ ...result, mode: resolvedMode, shouldShowSources: false });
  }

  if (resolvedMode === "story" && storyType !== "web_story") {
    const result = mock.originalStory(query, userProfile);
    await logSearchQuery({ userQuery: query, queryMode: resolvedMode, usedProvider: result.provider });
    return responseShape({ ...result, mode: resolvedMode, shouldShowSources: false });
  }

  let provider = "mock_fallback";
  let confidence = "low";
  let results = [];
  let webAnswer = "";

  if (resolvedMode === "health_tip") {
    if (routed.needsWebSearch) {
      const web = await runWebSearch(query);
      if (web?.results?.length) {
        provider = web.provider;
        confidence = web.confidence;
        results = web.results;
        webAnswer = web.answer;
      }
    } else {
      const local = await searchLocalIndex({ query, mode: resolvedMode });
      if (local.results.length > 0) {
        provider = local.provider;
        confidence = local.confidence;
        results = local.results;
      } else {
        const web = await runWebSearch(query);
        if (web?.results?.length) {
          provider = web.provider;
          confidence = web.confidence;
          results = web.results;
          webAnswer = web.answer;
        }
      }
    }
  } else if (
    resolvedMode === "news" ||
    resolvedMode === "general_web_search" ||
    resolvedMode === "weather" ||
    (resolvedMode === "story" && storyType === "web_story")
  ) {
    const web = await runWebSearch(query);
    if (web?.results?.length || web?.answer) {
      provider = web.provider;
      confidence = web.confidence;
      results = web.results || [];
      webAnswer = web.answer || "";
    }
  }

  if (!results.length && !webAnswer) {
    const fallback = mock.fallback(resolvedMode);
    await logSearchQuery({ userQuery: query, queryMode: resolvedMode, usedProvider: fallback.provider });
    return responseShape({ ...fallback, mode: resolvedMode, shouldShowSources: false });
  }

  results = filterTrustedSources(results);
  if (!results.length) {
    const fallback = mock.fallback(resolvedMode);
    await logSearchQuery({ userQuery: query, queryMode: resolvedMode, usedProvider: "untrusted_filtered" });
    return responseShape({ ...fallback, mode: resolvedMode, shouldShowSources: false });
  }

  const summarized = await summarizeWithAi({
    query,
    mode: resolvedMode,
    results,
    webAnswer,
  });
  const sources = summarized.sources?.length ? summarized.sources : toSources(results);
  await logSearchQuery({
    userQuery: query,
    queryMode: resolvedMode,
    usedProvider: provider,
    results,
  });

  return responseShape({
    answer: summarized.answer || webAnswer,
    summary: summarized.summary || "",
    sources,
    mode: resolvedMode,
    provider,
    toolUsed: provider === "web_search" ? "web_search" : provider,
    confidence,
    shouldShowSources: sources.length > 0,
  });
}

module.exports = {
  search,
};
