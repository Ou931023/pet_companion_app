#!/usr/bin/env node
//
// Care Alert Demo 腳本（CR-0003 Batch 1）。
//
// 目的：用可重現的範例資料，展示 Care Alert 的完整後端流程：
//   建立 alert（low/medium/high/urgent）
//   → store 持久化
//   → Telegram 推播門檻（只有 high/urgent 才推、套 cooldown 防洗版）
//   → 狀態流程 new → acknowledged → resolved
//
// 安全保證：
// - 一律寫入 os.tmpdir() 的暫存檔，**絕不寫入正式 backend/stt_proxy/data/*.json**。
// - 不實際呼叫 Telegram API（只用 buildMessage 預覽訊息），避免意外外送。
//   （真正的 Telegram live demo 請改用實機後端 + 你自己的 .env，本腳本只示範流程。）
//
// 用法：
//   node scripts/care_alert_demo.js

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 強制把 store 導到暫存檔（覆寫任何既有設定），保證不碰正式 data。
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "care_alert_demo_"));
const dataFile = path.join(tmpDir, "care_alerts.json");
process.env.CARE_ALERTS_DATA_FILE = dataFile;

const store = require("../services/careAlertStoreService");
const {
  buildMessage,
  shouldNotify,
} = require("../services/telegramNotifyService");
const {
  canSendTelegram,
  markTelegramSent,
} = require("../services/careAlertCooldown");

const SAMPLES = [
  {
    riskLevel: "low",
    riskLevelLabel: "一般",
    category: "other",
    categoryLabel: "其他",
    triggerSummary: "長者今天心情不錯，提到下午去公園散步。",
    transcriptSnippet: "今天天氣很好，我下午去公園走了走。",
    createdAt: "2026-05-31T09:00:00.000",
    source: "companion_analysis",
  },
  {
    riskLevel: "medium",
    riskLevelLabel: "持續觀察",
    category: "sleep",
    categoryLabel: "睡眠狀況",
    triggerSummary: "長者連續幾天提到睡不好，建議持續觀察作息。",
    transcriptSnippet: "我最近都睡不好，半夜一直醒。",
    createdAt: "2026-05-31T09:30:00.000",
    source: "companion_analysis",
  },
  {
    riskLevel: "high",
    riskLevelLabel: "需通知",
    category: "depressed",
    categoryLabel: "情緒低落",
    triggerSummary:
      "長者多次表達強烈無助與難過，建議家人今天主動關心並陪伴。",
    transcriptSnippet: "每天都好難過，覺得沒有人需要我。",
    createdAt: "2026-05-31T10:00:00.000",
    source: "companion_analysis",
  },
  {
    riskLevel: "urgent",
    riskLevelLabel: "緊急",
    category: "fall",
    categoryLabel: "跌倒",
    triggerSummary: "長者表示剛剛跌倒、身體不適，建議立即聯絡與協助。",
    transcriptSnippet: "我剛剛在浴室跌倒了，現在很痛。",
    createdAt: "2026-05-31T10:15:00.000",
    source: "companion_analysis",
  },
];

function line(s = "") {
  process.stdout.write(`${s}\n`);
}

(async () => {
  line("=== Care Alert Demo（資料寫入暫存檔，正式 data 不受影響）===");
  line(`暫存資料檔：${dataFile}`);
  line("");

  for (const sample of SAMPLES) {
    const saved = await store.saveAlert(sample);
    const lvl = sample.riskLevel;
    const eligible = shouldNotify(sample);
    const key = `${sample.source}::${store.normalizeRiskLevel(lvl)}`;

    line(`[${lvl.toUpperCase()}] ${sample.triggerSummary}`);
    line(`  store：${saved.success ? "已存入" : "存入失敗"}（status=${saved.alert?.status}）`);

    if (!eligible) {
      line("  Telegram：略過（low/medium 只進 store / caregiver_web，不推播）");
    } else if (!canSendTelegram(key)) {
      line("  Telegram：略過（cooldown 冷卻中，避免洗版）");
    } else {
      markTelegramSent(key);
      line("  Telegram：將推播（high/urgent）。訊息預覽：");
      buildMessage(sample)
        .split("\n")
        .forEach((l) => line(`    | ${l}`));
    }
    line("");
  }

  // 防洗版示範：同一筆 urgent 立刻再來一次（預設 cooldown 啟用時應被擋）。
  const dup = SAMPLES[3];
  const dupKey = `${dup.source}::${store.normalizeRiskLevel(dup.riskLevel)}`;
  line("=== 防洗版示範：立即重複同一筆 urgent ===");
  line(
    canSendTelegram(dupKey)
      ? "  可再次推播（cooldown 已關閉或已到期）"
      : "  已被 cooldown 擋下，不重複推播 ✅",
  );
  line("");

  // 狀態流程示範：取最新一筆，走 new → acknowledged → resolved。
  const list = await store.listAlerts({ limit: 1 });
  const target = list[0];
  line("=== 狀態流程示範（new → acknowledged → resolved）===");
  line(`  目標 alert id=${target.id} 目前 status=${target.status}`);
  const ack = await store.updateAlertStatus(target.id, "acknowledged");
  line(`  → acknowledged：${ack.success ? "成功" : ack.error}`);
  const resolved = await store.updateAlertStatus(target.id, "resolved");
  line(`  → resolved：${resolved.success ? "成功" : resolved.error}`);
  line("");
  line("Demo 結束。正式 runtime data 未被修改。");
})();
