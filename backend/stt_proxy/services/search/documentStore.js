const fs = require("fs/promises");
const path = require("path");
const { randomUUID } = require("crypto");
const pool = require("../../db/pool");

const dataDir = path.join(__dirname, "../../data");
const mockPath = path.join(dataDir, "mockCrawledDocuments.json");
const jsonStorePath = path.join(dataDir, "crawled_documents.json");
const queryLogPath = path.join(dataDir, "search_queries.json");
const resultLogPath = path.join(dataDir, "search_results.json");

function usePostgres() {
  return process.env.SEARCH_STORAGE === "postgres" && Boolean(process.env.DATABASE_URL);
}

async function readJson(filePath, fallback) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (_) {
    return fallback;
  }
}

async function writeJson(filePath, data) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

function normalizeDocument(doc) {
  const now = new Date().toISOString();
  return {
    id: doc.id || randomUUID(),
    title: (doc.title || "未命名來源").toString().trim(),
    url: (doc.url || "").toString().trim(),
    siteName: (doc.siteName || doc.site_name || "").toString().trim(),
    domain: (doc.domain || "").toString().trim(),
    publishedAt: doc.publishedAt || doc.published_at || null,
    crawledAt: doc.crawledAt || doc.crawled_at || now,
    content: (doc.content || "").toString().trim(),
    summary: (doc.summary || "").toString().trim(),
    category: doc.category || "general_web_search",
    sourceType: doc.sourceType || doc.source_type || "local_index",
    isActive: doc.isActive ?? doc.is_active ?? true,
  };
}

async function seedJsonStoreIfNeeded() {
  const existing = await readJson(jsonStorePath, null);
  if (Array.isArray(existing) && existing.length > 0) return existing;
  const mockDocs = await readJson(mockPath, []);
  const docs = mockDocs.map(normalizeDocument);
  await writeJson(jsonStorePath, docs);
  return docs;
}

async function listDocuments() {
  if (usePostgres()) {
    try {
      const result = await pool.query(
        `SELECT id, title, url, site_name, domain, published_at, crawled_at,
                content, summary, category, source_type, is_active
         FROM crawled_documents
         WHERE is_active = true
         ORDER BY crawled_at DESC
         LIMIT 200`,
      );
      return result.rows.map(normalizeDocument);
    } catch (error) {
      console.error("[search-store] postgres list failed, falling back to json", error?.message || error);
    }
  }
  return seedJsonStoreIfNeeded();
}

async function upsertDocument(document) {
  const doc = normalizeDocument(document);
  if (!doc.url) throw new Error("document url is required");

  if (usePostgres()) {
    try {
      const result = await pool.query(
        `INSERT INTO crawled_documents (
           title, url, site_name, domain, published_at, crawled_at, content,
           summary, category, source_type, is_active
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
         ON CONFLICT (url) DO UPDATE SET
           title = EXCLUDED.title,
           site_name = EXCLUDED.site_name,
           domain = EXCLUDED.domain,
           published_at = EXCLUDED.published_at,
           crawled_at = EXCLUDED.crawled_at,
           content = EXCLUDED.content,
           summary = EXCLUDED.summary,
           category = EXCLUDED.category,
           source_type = EXCLUDED.source_type,
           is_active = EXCLUDED.is_active
         RETURNING *`,
        [
          doc.title,
          doc.url,
          doc.siteName,
          doc.domain,
          doc.publishedAt,
          doc.crawledAt,
          doc.content,
          doc.summary,
          doc.category,
          doc.sourceType,
          doc.isActive,
        ],
      );
      return normalizeDocument(result.rows[0]);
    } catch (error) {
      console.error("[search-store] postgres upsert failed, falling back to json", error?.message || error);
    }
  }

  const docs = await seedJsonStoreIfNeeded();
  const index = docs.findIndex((item) => item.url === doc.url);
  if (index >= 0) docs[index] = { ...docs[index], ...doc };
  else docs.push(doc);
  await writeJson(jsonStorePath, docs);
  return doc;
}

async function logSearchQuery({ userQuery, queryMode, usedProvider, results = [] }) {
  const queryId = randomUUID();
  const createdAt = new Date().toISOString();

  if (usePostgres()) {
    try {
      const queryResult = await pool.query(
        `INSERT INTO search_queries (id, user_query, query_mode, used_provider, created_at)
         VALUES ($1,$2,$3,$4,$5)
         RETURNING id`,
        [queryId, userQuery, queryMode, usedProvider, createdAt],
      );
      for (const [index, item] of results.entries()) {
        await pool.query(
          `INSERT INTO search_results (
             query_id, document_id, title, url, snippet, rank, created_at
           ) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
          [
            queryResult.rows[0].id,
            item.id || null,
            item.title || "",
            item.url || "",
            item.snippet || item.summary || "",
            index + 1,
            createdAt,
          ],
        );
      }
      return queryResult.rows[0].id;
    } catch (error) {
      console.error("[search-store] postgres query log failed, falling back to json", error?.message || error);
    }
  }

  const queries = await readJson(queryLogPath, []);
  queries.push({ id: queryId, userQuery, queryMode, usedProvider, createdAt });
  await writeJson(queryLogPath, queries.slice(-500));

  const resultLogs = await readJson(resultLogPath, []);
  results.forEach((item, index) => {
    resultLogs.push({
      id: randomUUID(),
      queryId,
      documentId: item.id || null,
      title: item.title || "",
      url: item.url || "",
      snippet: item.snippet || item.summary || "",
      rank: index + 1,
      createdAt,
    });
  });
  await writeJson(resultLogPath, resultLogs.slice(-1000));
  return queryId;
}

module.exports = {
  listDocuments,
  upsertDocument,
  logSearchQuery,
};
