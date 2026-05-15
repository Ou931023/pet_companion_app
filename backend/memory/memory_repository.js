const {
  createMemory,
  listMemories,
  searchMemoriesByEmbedding,
  archiveMemory,
  findDuplicateMemory,
} = require("../stt_proxy/services/memory/memoryStore");

async function createLongTermMemory(memory) {
  return createMemory(memory);
}

async function listLongTermMemories(userId) {
  return listMemories(userId);
}

async function retrieveByEmbedding(userId, embedding, topK = 5) {
  return searchMemoriesByEmbedding(userId, embedding, topK);
}

async function archiveLongTermMemory(memoryId, userId) {
  return archiveMemory(memoryId, userId);
}

module.exports = {
  createLongTermMemory,
  listLongTermMemories,
  retrieveByEmbedding,
  archiveLongTermMemory,
  findDuplicateMemory,
};
