const assert = require("node:assert/strict");
const { test, afterEach } = require("node:test");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

process.env.NODE_ENV = "test";

const store = require("./appUsageEventStore");

afterEach(() => {
  store.setPgForTest(null);
});

async function tempFile() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "app-usage-"));
  return path.join(dir, "events.json");
}

test("normalizeEvent 只接受允許的事件類型，metadata 只保留安全 primitive", () => {
  const event = store.normalizeEvent(
    {
      eventType: "pet_interaction",
      eventAt: "2026-06-15T10:00:00.000Z",
      sessionId: "s".repeat(100),
      durationMs: 999999999,
      metadata: {
        source: "pet_tap",
        nested: { nope: true },
        list: [1, 2],
        ok: true,
        count: 2,
        long: "x".repeat(140),
      },
    },
    { elderId: "elder-1", userId: "user-1" },
  );

  assert.equal(event.eventType, "pet_interaction");
  assert.equal(event.elderId, "elder-1");
  assert.equal(event.sessionId.length, 80);
  assert.equal(event.durationMs, 24 * 60 * 60 * 1000);
  assert.deepEqual(Object.keys(event.metadata).sort(), ["count", "long", "ok", "source"]);
  assert.equal(event.metadata.long.length, 120);
});

test("invalid event type 會拒絕", () => {
  assert.throws(
    () => store.normalizeEvent({ eventType: "fake_demo_event" }, { elderId: "e" }),
    /invalid_event_type/,
  );
});

test("JSON fallback：recordEvent 寫入，getUsageStats 聚合後台可用數據", async () => {
  const eventsFilePath = await tempFile();
  const pg = { isPostgresAvailable: async () => false };
  const caller = { elderId: "elder-1", userId: "user-1" };

  await store.recordEvent(
    { eventType: "app_open", eventAt: "2026-06-15T09:00:00.000Z" },
    caller,
    { pg, eventsFilePath },
  );
  await store.recordEvent(
    {
      eventType: "voice_interaction_start",
      eventAt: "2026-06-15T09:05:00.000Z",
      sessionId: "session-1",
    },
    caller,
    { pg, eventsFilePath },
  );
  await store.recordEvent(
    {
      eventType: "voice_interaction_end",
      eventAt: "2026-06-15T09:06:00.000Z",
      sessionId: "session-1",
      durationMs: 60000,
    },
    caller,
    { pg, eventsFilePath },
  );
  await store.recordEvent(
    {
      eventType: "voice_navigation",
      eventAt: "2026-06-15T09:06:30.000Z",
      sessionId: "session-1",
      metadata: { route: "/daily-care-tasks", source: "realtime_voice" },
    },
    caller,
    { pg, eventsFilePath },
  );
  await store.recordEvent(
    {
      eventType: "pet_interaction",
      eventAt: "2026-06-15T09:07:00.000Z",
      metadata: { petType: "dog", mood: "happy", satiety: 88, intimacy: 42 },
    },
    caller,
    { pg, eventsFilePath },
  );

  const stats = await store.getUsageStats("elder-1", {
    pg,
    eventsFilePath,
    nowIso: "2026-06-15T12:00:00.000Z",
    rangeDays: 7,
  });

  assert.equal(stats.available, true);
  assert.equal(stats.totalEvents, 5);
  assert.equal(stats.activeDays, 1);
  assert.equal(stats.voiceInteractions, 1);
  assert.equal(stats.voiceNavigations, 1);
  assert.equal(stats.petInteractions, 1);
  assert.equal(stats.totalDurationMs, 60000);
  assert.equal(stats.lastEventAt, "2026-06-15T09:07:00.000Z");
  assert.deepEqual(stats.latestPetMetadata, {
    petType: "dog",
    mood: "happy",
    satiety: 88,
    intimacy: 42,
  });
});

test("Postgres 可用時使用 app_usage_events INSERT，不落 JSON", async () => {
  const calls = [];
  const pg = {
    isPostgresAvailable: async () => true,
    query: async (sql, params) => {
      calls.push({ sql, params });
      return {
        rows: [
          {
            id: params[0],
            elder_id: params[1],
            user_id: params[2],
            event_type: params[3],
            event_at: params[4],
            session_id: params[5],
            duration_ms: params[6],
            metadata_json: params[7],
            created_at: "2026-06-15T09:00:00.000Z",
          },
        ],
      };
    },
  };

  const event = await store.recordEvent(
    { eventType: "typed_chat_sent", metadata: { source: "home_text_bar" } },
    { elderId: "elder-db", userId: "user-db" },
    { pg },
  );

  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /INSERT INTO app_usage_events/i);
  assert.equal(calls[0].params[1], "elder-db");
  assert.equal(event.eventType, "typed_chat_sent");
});
