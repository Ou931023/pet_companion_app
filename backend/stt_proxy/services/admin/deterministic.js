// 確定性序列產生器（CR-0007 Batch 2）。
//
// 健康後台的生理 / 情緒 / 遊戲指標在 demo 階段「不串智慧手環」，改以「以 elderId 為
// 種子的確定性 PRNG」產生穩定、可重現、落在合理區間的序列：
//   - 同一個 elderId 每次呼叫都回完全相同的資料（可重現，方便 demo 與測試）。
//   - 絕不使用 Math.random（不可重現）。
//
// 做法：用 FNV-1a 把字串 hash 成 32-bit 整數當 seed，再用 mulberry32 這個小型確定性
// PRNG 產生 [0,1) 浮點數。所有數值都用這條 PRNG 推導，因此完全由 elderId 決定。

// FNV-1a 32-bit 字串 hash（確定性，無外部依賴）。
function hashSeed(text) {
  let hash = 0x811c9dc5;
  const str = String(text == null ? "" : text);
  for (let i = 0; i < str.length; i += 1) {
    hash ^= str.charCodeAt(i);
    // 乘上 FNV prime，保持在 32-bit 範圍（>>> 0）。
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

// mulberry32：輸入 32-bit 整數 seed，回傳每次呼叫吐出 [0,1) 的確定性函式。
function mulberry32(seed) {
  let state = seed >>> 0;
  return function next() {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// 以 elderId（可選 salt，用來在同一長者下產生多條互不相同但各自確定的序列）建立 PRNG。
function createRng(elderId, salt = "") {
  return mulberry32(hashSeed(`${elderId}::${salt}`));
}

// 把 [0,1) 映射到 [min,max] 的浮點數，並四捨五入到 decimals 位。
function floatInRange(rng, min, max, decimals = 2) {
  const value = min + rng() * (max - min);
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

// 把 [0,1) 映射到 [min,max] 的整數（含端點）。
function intInRange(rng, min, max) {
  return Math.floor(min + rng() * (max - min + 1));
}

module.exports = {
  hashSeed,
  mulberry32,
  createRng,
  floatInRange,
  intInRange,
};
