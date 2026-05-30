// 健康指標序列產生與判定（CR-0007 Batch 2）。
//
// 生理 / 情緒 / 遊戲三類序列皆以 elderId 為種子的確定性產生器產生（見 deterministic.js），
// 同一 elderId 多次呼叫結果完全相同。數值落在合理生活區間。
//
// 判定規則（明確、寫在程式註解，供後台「情緒異常 / 遊戲退化」標記）：
//   - 情緒異常：近 7 日「負向情緒」占比 > NEGATIVE_RATIO_THRESHOLD（0.5）→ abnormal=true。
//   - 遊戲退化：cognitiveScore 趨勢下降（後半段平均 < 前半段平均 - DECLINE_MARGIN）
//     且最近一筆 < 基線（首日值）→ trend='declining' 且 abnormal=true。

const { createRng, floatInRange, intInRange } = require("./deterministic");

const DAYS = 14; // 預設產生最近 14 天序列。
const NEGATIVE_RATIO_THRESHOLD = 0.5;
const DECLINE_MARGIN = 6; // cognitiveScore（0~100）下降幅度門檻。

const POSITIVE_EMOTIONS = ["平靜", "開心", "放鬆", "滿足"];
const NEGATIVE_EMOTIONS = ["孤單", "低落", "焦慮", "煩躁"];

const SLEEP_QUALITY_BY_HOURS = (hours) => {
  if (hours >= 7) return "良好";
  if (hours >= 6) return "尚可";
  return "偏少";
};

// 產生最近 DAYS 天的日期字串（由舊到新），以固定錨點日期計算，確保確定性。
// 用固定錨點（非 new Date()）讓序列日期也可重現、與時間無關。
function buildDates(days = DAYS, anchorIso = "2026-05-31T00:00:00.000Z") {
  const anchor = new Date(anchorIso);
  const dates = [];
  for (let i = days - 1; i >= 0; i -= 1) {
    const d = new Date(anchor.getTime() - i * 24 * 60 * 60 * 1000);
    dates.push(d.toISOString().slice(0, 10));
  }
  return dates;
}

// ---- 生理 / 生活指標 ----

function buildPhysioSeries(elderId, options = {}) {
  const days = options.days || DAYS;
  const dates = buildDates(days, options.anchorIso);
  const rng = createRng(elderId, "physio");
  return dates.map((date) => {
    const sleepHours = floatInRange(rng, 4.5, 8.5, 1); // 合理睡眠 4~9 小時。
    return {
      date,
      dailyInteractionMinutes: intInRange(rng, 5, 60), // 互動分鐘 5~60。
      reminderCompletionRate: floatInRange(rng, 0.4, 1, 2), // 完成率 0~1。
      medicationCompletionRate: floatInRange(rng, 0.5, 1, 2),
      waterCompletionRate: floatInRange(rng, 0.3, 1, 2),
      exerciseCompletionRate: floatInRange(rng, 0.2, 1, 2),
      sleepHours,
      sleepQuality: SLEEP_QUALITY_BY_HOURS(sleepHours),
    };
  });
}

function avg(nums) {
  if (nums.length === 0) return 0;
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}

function summarizePhysio(series) {
  return {
    avgDailyInteractionMinutes: Math.round(
      avg(series.map((s) => s.dailyInteractionMinutes)),
    ),
    avgReminderCompletionRate:
      Math.round(avg(series.map((s) => s.reminderCompletionRate)) * 100) / 100,
    avgMedicationCompletionRate:
      Math.round(avg(series.map((s) => s.medicationCompletionRate)) * 100) / 100,
    avgWaterCompletionRate:
      Math.round(avg(series.map((s) => s.waterCompletionRate)) * 100) / 100,
    avgExerciseCompletionRate:
      Math.round(avg(series.map((s) => s.exerciseCompletionRate)) * 100) / 100,
    avgSleepHours:
      Math.round(avg(series.map((s) => s.sleepHours)) * 10) / 10,
  };
}

function getPhysio(elderId, options = {}) {
  const series = buildPhysioSeries(elderId, options);
  return { series, summary: summarizePhysio(series) };
}

// ---- 情緒序列 ----

function buildEmotionSeries(elderId, options = {}) {
  const days = options.days || DAYS;
  const dates = buildDates(days, options.anchorIso);
  const rng = createRng(elderId, "emotion");
  return dates.map((date) => {
    // 以確定性機率決定當日偏正向或偏負向。
    const negative = rng() < 0.35;
    const pool = negative ? NEGATIVE_EMOTIONS : POSITIVE_EMOTIONS;
    const emotion = pool[intInRange(rng, 0, pool.length - 1)];
    // score：負向情緒分數偏低（0~0.45），正向偏高（0.55~1）。
    const score = negative
      ? floatInRange(rng, 0.1, 0.45, 2)
      : floatInRange(rng, 0.55, 0.95, 2);
    return {
      date,
      emotion,
      score,
      summary: negative
        ? `當天情緒偏向${emotion}，可多給一些陪伴。`
        : `當天情緒${emotion}，狀態穩定。`,
    };
  });
}

// 情緒異常判定：近 7 日負向情緒占比 > 門檻 → abnormal。
function analyzeEmotion(series) {
  const recent = series.slice(-7);
  const negativeCount = recent.filter((s) =>
    NEGATIVE_EMOTIONS.includes(s.emotion),
  ).length;
  const negativeRatio = recent.length ? negativeCount / recent.length : 0;
  const abnormal = negativeRatio > NEGATIVE_RATIO_THRESHOLD;

  // dominantEmotion：近 7 日出現次數最多的情緒。
  const counts = {};
  for (const s of recent) {
    counts[s.emotion] = (counts[s.emotion] || 0) + 1;
  }
  let dominantEmotion = recent.length ? recent[recent.length - 1].emotion : "平靜";
  let max = -1;
  for (const [emotion, count] of Object.entries(counts)) {
    if (count > max) {
      max = count;
      dominantEmotion = emotion;
    }
  }
  return { dominantEmotion, abnormal, negativeRatio };
}

function getEmotion(elderId, options = {}) {
  const series = buildEmotionSeries(elderId, options);
  const { dominantEmotion, abnormal } = analyzeEmotion(series);
  return { series, dominantEmotion, abnormal };
}

// 白話心理摘要（給 /elders/:id 的 psych 區塊）。
function buildPsych(elderId, options = {}) {
  const series = buildEmotionSeries(elderId, options);
  const { dominantEmotion, abnormal } = analyzeEmotion(series);
  const summary = abnormal
    ? `最近一週情緒以${dominantEmotion}為主，負向情緒偏多，建議多陪伴關心。`
    : `最近一週情緒大致平穩，以${dominantEmotion}為主。`;
  return { summary, dominantEmotion, abnormal };
}

// ---- 遊戲認知序列 ----

const GAME_TYPES = ["記憶配對", "數字接龍", "看圖找物"];

function buildGameSeries(elderId, options = {}) {
  const days = options.days || DAYS;
  const dates = buildDates(days, options.anchorIso);
  const rng = createRng(elderId, "game");
  // 以 elderId 決定整體趨勢方向：部分長者呈現認知分數緩降（用於 demo 退化案例）。
  const declining = rng() < 0.4;
  const baseline = floatInRange(rng, 60, 85, 0); // 認知基線分數 60~85。
  return dates.map((date, index) => {
    // 趨勢項：declining 者隨天數線性下降，否則小幅波動。
    const trendDelta = declining
      ? -(index / (days - 1)) * floatInRange(rng, 10, 20, 1)
      : floatInRange(rng, -4, 4, 1);
    const noise = floatInRange(rng, -3, 3, 1);
    let cognitiveScore = Math.round((baseline + trendDelta + noise) * 10) / 10;
    cognitiveScore = Math.max(0, Math.min(100, cognitiveScore));
    return {
      date,
      gameType: GAME_TYPES[intInRange(rng, 0, GAME_TYPES.length - 1)],
      cognitiveScore,
      completionRate: floatInRange(rng, 0.4, 1, 2),
      durationSeconds: intInRange(rng, 60, 360),
      regressionFlag: false, // 由 analyzeGame 統一回填趨勢層級的退化旗標。
    };
  });
}

// 遊戲退化判定：後半段平均 cognitiveScore < 前半段平均 - DECLINE_MARGIN
// 且最近一筆 < 基線（首筆）→ trend='declining' 且 abnormal=true。
function analyzeGame(series) {
  if (series.length < 4) {
    return { trend: "stable", abnormal: false };
  }
  const mid = Math.floor(series.length / 2);
  const firstHalfAvg = avg(series.slice(0, mid).map((s) => s.cognitiveScore));
  const secondHalfAvg = avg(series.slice(mid).map((s) => s.cognitiveScore));
  const baseline = series[0].cognitiveScore;
  const latest = series[series.length - 1].cognitiveScore;

  const declining =
    secondHalfAvg < firstHalfAvg - DECLINE_MARGIN && latest < baseline;
  return {
    trend: declining ? "declining" : "stable",
    abnormal: declining,
  };
}

function getGameMetrics(elderId, options = {}) {
  const series = buildGameSeries(elderId, options);
  const { trend, abnormal } = analyzeGame(series);
  // 退化時把後半段標記 regressionFlag，方便前台顯示哪幾天偏低。
  if (abnormal) {
    const mid = Math.floor(series.length / 2);
    for (let i = mid; i < series.length; i += 1) {
      series[i].regressionFlag = series[i].cognitiveScore < series[0].cognitiveScore;
    }
  }
  return { series, trend, abnormal };
}

module.exports = {
  DAYS,
  NEGATIVE_EMOTIONS,
  POSITIVE_EMOTIONS,
  buildDates,
  getPhysio,
  getEmotion,
  getGameMetrics,
  buildPsych,
  analyzeEmotion,
  analyzeGame,
};
