"use strict";

const fs = require("fs/promises");
const path = require("path");
const { randomUUID } = require("crypto");

const defaultPg = require("../db/postgres");
const {
  isJsonFallbackAllowed,
  FeatureUnavailableInProductionError,
} = require("../config/env");

const DEFAULT_EVENTS_FILE = path.join(__dirname, "..", "data", "app_usage_events.json");
const VALID_EVENT_TYPES = new Set([
  "app_open",
  "app_background",
  "session_start",
  "session_end",
  "voice_interaction_start",
  "voice_interaction_end",
  "voice_navigation",
  "typed_chat_sent",
  "pet_interaction",
  "reminder_created",
  "daily_task_completed",
  "photo_verification_submitted",
  "puzzle_started",
  "puzzle_completed",
  "font_size_changed",
  "pet_style_changed",
]);

let activePg = defaultPg;

function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

function resolveEventsFile(options = {}) {
  return options.eventsFilePath || process.env.APP_USAGE_EVENTS_DATA_FILE || DEFAULT_EVENTS_FILE;
}

async function isDbAvailable(pg) {
  if (!pg || typeof pg.isPostgresAvailable !== "function") return false;
  try {
    return await pg.isPostgresAvailable();
  } catch (_error) {
    return false;
  }
}

function nowIso() {
  return new Date().toISOString();
}

function toIso(value) {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  return value;
}

function safeMetadata(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const out = {};
  for (const [key, raw] of Object.entries(value)) {
    if (raw == null) continue;
    if (typeof raw === "string") out[key] = raw.slice(0, 120);
    else if (typeof raw === "number" && Number.isFinite(raw)) out[key] = raw;
    else if (typeof raw === "boolean") out[key] = raw;
  }
  return out;
}

function normalizeDuration(value) {
  if (value == null || value === "") return null;
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.min(n, 24 * 60 * 60 * 1000);
}

function normalizeEvent(payload = {}, caller = {}) {
  const eventType = String(payload.eventType || payload.event_type || "").trim();
  if (!VALID_EVENT_TYPES.has(eventType)) {
    const error = new Error("invalid_event_type");
    error.code = "invalid_event_type";
    throw error;
  }
  const eventAt = payload.eventAt || payload.event_at || nowIso();
  const parsedAt = new Date(eventAt);
  return {
    id: payload.id || randomUUID(),
    elderId: String(caller.elderId || "").trim(),
    userId: caller.userId == null ? null : String(caller.userId),
    eventType,
    eventAt: Number.isNaN(parsedAt.getTime()) ? nowIso() : parsedAt.toISOString(),
    sessionId: payload.sessionId == null ? null : String(payload.sessionId).slice(0, 80),
    durationMs: normalizeDuration(payload.durationMs || payload.duration_ms),
    metadata: safeMetadata(payload.metadata),
    createdAt: nowIso(),
  };
}

async function readJson(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error && error.code !== "ENOENT") {
      console.error("[app-usage] read failed, treating as empty", {
        error: error.message,
      });
    }
    return [];
  }
}

async function writeJson(filePath, rows) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(rows, null, 2), "utf8");
}

function rowToEvent(row) {
  return {
    id: row.id,
    elderId: row.elder_id,
    userId: row.user_id || null,
    eventType: row.event_type,
    eventAt: toIso(row.event_at),
    sessionId: row.session_id || null,
    durationMs: row.duration_ms == null ? null : Number(row.duration_ms),
    metadata: row.metadata_json || {},
    createdAt: toIso(row.created_at),
  };
}

async function recordEvent(payload, caller, options = {}) {
  const event = normalizeEvent(payload, caller);
  if (!event.elderId) {
    const error = new Error("resident_not_linked");
    error.code = "resident_not_linked";
    throw error;
  }

  const pg = options.pg || activePg;
  if (await isDbAvailable(pg)) {
    const result = await pg.query(
      `INSERT INTO app_usage_events (
        id, elder_id, user_id, event_type, event_at, session_id, duration_ms, metadata_json
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
      RETURNING id, elder_id, user_id, event_type, event_at, session_id, duration_ms, metadata_json, created_at`,
      [
        event.id,
        event.elderId,
        event.userId,
        event.eventType,
        event.eventAt,
        event.sessionId,
        event.durationMs,
        event.metadata,
      ],
    );
    return rowToEvent(result.rows[0]);
  }

  if (!isJsonFallbackAllowed()) {
    throw new FeatureUnavailableInProductionError();
  }

  const filePath = resolveEventsFile(options);
  const rows = await readJson(filePath);
  rows.push(event);
  await writeJson(filePath, rows);
  return event;
}

function inRange(event, nowIsoValue, rangeDays) {
  const day = String(event.eventAt || "").slice(0, 10);
  if (!day) return false;
  const end = new Date(String(nowIsoValue).slice(0, 10) + "T00:00:00.000Z");
  const start = new Date(end.getTime() - (rangeDays - 1) * 24 * 60 * 60 * 1000);
  const d = new Date(day + "T00:00:00.000Z");
  return d >= start && d <= end;
}

async function listEvents(options = {}) {
  const elderId = String(options.elderId || "").trim();
  const rangeDays = Math.max(1, Math.min(90, Math.floor(Number(options.rangeDays) || 7)));
  const now = options.nowIso || nowIso();
  const pg = options.pg || activePg;

  if (await isDbAvailable(pg)) {
    const result = await pg.query(
      `SELECT id, elder_id, user_id, event_type, event_at, session_id, duration_ms, metadata_json, created_at
       FROM app_usage_events
       WHERE elder_id = $1
         AND event_at >= (($2::timestamptz)::date - (($3::int - 1) * interval '1 day'))
         AND event_at < (($2::timestamptz)::date + interval '1 day')
       ORDER BY event_at DESC
       LIMIT 1000`,
      [elderId, now, rangeDays],
    );
    return result.rows.map(rowToEvent);
  }

  if (!isJsonFallbackAllowed()) {
    throw new FeatureUnavailableInProductionError();
  }

  const rows = await readJson(resolveEventsFile(options));
  return rows
    .filter((event) => String(event.elderId) === elderId && inRange(event, now, rangeDays))
    .sort((a, b) => String(b.eventAt).localeCompare(String(a.eventAt)))
    .slice(0, 1000);
}

async function getUsageStats(elderId, options = {}) {
  const events = Array.isArray(options.events)
    ? options.events
    : await listEvents({ ...options, elderId });
  const byType = {};
  let totalDurationMs = 0;
  let lastEventAt = null;
  const activeDays = new Set();
  let latestPetEvent = null;

  for (const event of events) {
    byType[event.eventType] = (byType[event.eventType] || 0) + 1;
    if (event.durationMs) totalDurationMs += Number(event.durationMs) || 0;
    if (event.eventAt) {
      activeDays.add(String(event.eventAt).slice(0, 10));
      if (!lastEventAt || String(event.eventAt) > String(lastEventAt)) lastEventAt = event.eventAt;
    }
    if (event.eventType === "pet_interaction" || event.eventType === "pet_style_changed") {
      if (!latestPetEvent || String(event.eventAt) > String(latestPetEvent.eventAt)) {
        latestPetEvent = event;
      }
    }
  }

  return {
    available: events.length > 0,
    totalEvents: events.length,
    activeDays: activeDays.size,
    totalDurationMs,
    lastEventAt,
    byType,
    voiceInteractions:
      byType.voice_interaction_end || byType.voice_interaction_start || 0,
    voiceNavigations: byType.voice_navigation || 0,
    typedChats: byType.typed_chat_sent || 0,
    petInteractions: byType.pet_interaction || 0,
    remindersCreated: byType.reminder_created || 0,
    dailyTasksCompleted: byType.daily_task_completed || 0,
    puzzleCompletions: byType.puzzle_completed || 0,
    latestPetMetadata: latestPetEvent ? latestPetEvent.metadata || {} : {},
  };
}

module.exports = {
  VALID_EVENT_TYPES,
  normalizeEvent,
  recordEvent,
  listEvents,
  getUsageStats,
  setPgForTest,
};
