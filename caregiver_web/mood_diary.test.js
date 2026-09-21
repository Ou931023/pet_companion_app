// CR-0108: isolated executable UI tests, no environment files or live credentials.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

function functionSource(name) {
  const start = source.indexOf("  function " + name + "(");
  assert.ok(start >= 0, name);
  const end = source.indexOf("\n  }", start) + 4;
  return source.slice(start, end);
}

function element() {
  const classes = new Set();
  return {
    innerHTML: "", textContent: "", disabled: false, attributes: {},
    setAttribute(key, value) { this.attributes[key] = value; },
    classList: {
      add(name) { classes.add(name); },
      remove(name) { classes.delete(name); },
      contains(name) { return classes.has(name); },
      toggle(name, force) { if (force) classes.add(name); else classes.delete(name); },
    },
  };
}

function harness() {
  const storage = new Map([
    ["mode", "caregiver"], ["caregiver", "test-caregiver"], ["admin", "test-admin"],
  ]);
  const pending = [];
  const context = vm.createContext({
    elH: Object.fromEntries([
      "diaryEntries", "diaryStatus", "diaryRefresh", "elderAnalysis", "healthStatus",
    ].map(key => [key, element()])),
    residentDetailRevision: 0, moodDiaryRevision: 0, activeElderId: "resident-a",
    authState: { authMode: "caregiver" }, sessionInvalid: false,
    ADMIN_TOKEN_KEY: "admin", CAREGIVER_TOKEN_KEY: "caregiver", AUTH_MODE_KEY: "mode",
    SESSION_EXPIRED_MSG: "登入已失效，請重新登入",
    FORBIDDEN_MSG: "目前帳號沒有權限查看此資料", NEED_LOGIN_MSG: "請先登入",
    localStorage: {
      getItem(key) { return storage.get(key) || null; },
      setItem(key, value) { storage.set(key, value); },
      removeItem(key) { storage.delete(key); },
    },
    adminUrl: suffix => "/api/admin" + suffix,
    formatTime: value => "時間：" + value,
    document: { getElementById: () => null },
    showAuthMessage() {}, syncAdminTokenInputs() {}, applyAuthModeUi() {},
    renderProfile() {}, renderPhysio() {}, renderPsych() {}, renderEmotion() {},
    renderGame() {}, renderHealthAlerts() {},
    fetch(url, options) {
      return new Promise((resolve, reject) => pending.push({ url, options, resolve, reject }));
    },
  });
  for (const name of [
    "escapeHtml", "getAdminToken", "getCaregiverToken", "isSuperAdminMode",
    "isCaregiverMode", "getActiveToken", "hasActiveToken", "authHeaders",
    "loadAuthState", "applyLogin", "logout", "ensureCanFetch", "handleSessionExpired",
    "loadElderAnalysis", "resetResidentDetail", "residentDetailGuard",
    "setMoodDiaryStatus", "renderMoodDiary", "loadMoodDiary",
  ]) vm.runInContext(functionSource(name), context);
  return { c: context, pending, storage };
}

function respond(request, entries = [], status = 200) {
  request.resolve({ status, ok: status === 200, json: async () => ({ success: true, entries }) });
}

test("diary lives in resident detail after emotion history, not a navigation tab", () => {
  const detail = html.slice(html.indexOf('id="elder-analysis"'), html.indexOf('id="view-analytics"'));
  assert.ok(detail.indexOf('id="mood-diary-title"') > detail.indexOf('id="emotion-body"'));
  assert.ok(detail.includes('aria-live="polite"'));
  assert.ok(detail.includes('id="mood-diary-refresh"'));
  assert.doesNotMatch(html, /id="tab-[^"]*diary/);
  assert.match(functionSource("loadElderList"), /resetResidentDetail\(\)/);
});

for (const role of ["caregiver", "super_admin"]) {
  test(role + " uses its own credentials, no-store and only explicitly shared entries", async () => {
    const { c, pending } = harness();
    c.authState.authMode = role;
    c.activeElderId = "resident/a";
    const work = c.loadMoodDiary("resident/a");
    assert.equal(pending[0].url, "/api/admin/residents/resident%2Fa/mood-diary");
    assert.equal(pending[0].options.headers.Authorization,
      "Bearer test-" + (role === "caregiver" ? "caregiver" : "admin"));
    assert.equal(pending[0].options.cache, "no-store");
    assert.equal(c.elH.diaryRefresh.disabled, true);
    assert.equal(c.elH.diaryEntries.attributes["aria-busy"], "true");
    assert.match(c.elH.diaryStatus.textContent, /正在讀取/);
    respond(pending[0], [
      { sharedWithCaregiver: true, mood: "happy", content: "shared-text", createdAt: "2026-09-21T01:00:00Z" },
      ...[false, "true", 1, null, undefined].map(sharedWithCaregiver => ({ sharedWithCaregiver, content: "private-text" })),
      null,
    ]);
    await work;
    assert.match(c.elH.diaryEntries.innerHTML, /shared-text/);
    assert.match(c.elH.diaryEntries.innerHTML, /開心/);
    assert.doesNotMatch(c.elH.diaryEntries.innerHTML, /private-text/);
    assert.equal(c.elH.diaryEntries.attributes["aria-busy"], "false");
    assert.equal(c.elH.diaryRefresh.disabled, false);
  });
}

test("escapes mood/content, preserves line breaks, and handles invalid timestamps", () => {
  const { c } = harness();
  c.renderMoodDiary([{ sharedWithCaregiver: true, mood: '<img onerror="x">',
    content: '<script>alert("x")</script>\n&\'text', createdAt: "not-a-date" }]);
  const rendered = c.elH.diaryEntries.innerHTML;
  assert.doesNotMatch(rendered, /<img|<script/);
  assert.match(rendered, /&lt;img onerror=&quot;x&quot;&gt;/);
  assert.match(rendered, /\n&amp;&#39;text/);
  assert.match(rendered, /日期未提供/);
});

test("empty or exclusively private results show an honest empty state", () => {
  const { c } = harness();
  for (const entries of [[], [{ content: "private" }]]) {
    c.renderMoodDiary(entries);
    assert.equal(c.elH.diaryEntries.innerHTML, "");
    assert.match(c.elH.diaryStatus.textContent, /沒有已分享/);
  }
});

for (const status of [403, 404, 503]) {
  test(status + " clears prior entries and shows a safe error without response body", async () => {
    const { c, pending } = harness();
    c.elH.diaryEntries.innerHTML = "old-private-content";
    const work = c.loadMoodDiary("resident-a");
    assert.equal(c.elH.diaryEntries.innerHTML, "");
    pending[0].resolve({ status, ok: false, json() { assert.fail("must not read error body"); } });
    await work;
    assert.equal(c.elH.diaryEntries.innerHTML, "");
    assert.match(c.elH.diaryStatus.textContent, status === 403 ? /沒有權限/ : /暫時無法/);
    assert.equal(c.sessionInvalid, false);
    assert.equal(c.elH.diaryRefresh.disabled, false);
  });
}

test("401 invalidates session and prevents additional requests", async () => {
  const { c, pending } = harness();
  const work = c.loadMoodDiary("resident-a");
  respond(pending[0], [], 401);
  await work;
  assert.equal(c.sessionInvalid, true);
  assert.equal(c.elH.diaryEntries.innerHTML, "");
  assert.match(c.elH.diaryStatus.textContent, /登入已失效/);
  c.loadMoodDiary("resident-a");
  assert.equal(pending.length, 1);
});

test("malformed success, rejected JSON and network failure are not empty successes", async () => {
  for (const failure of ["shape", "json", "network"]) {
    const { c, pending } = harness();
    const work = c.loadMoodDiary("resident-a");
    if (failure === "network") pending[0].reject(new Error("sensitive backend detail"));
    else pending[0].resolve({ status: 200, ok: true, json: async () => {
      if (failure === "json") throw new Error("sensitive backend detail");
      return { entries: [] };
    } });
    await work;
    assert.match(c.elH.diaryStatus.textContent, /暫時無法/);
    assert.doesNotMatch(c.elH.diaryStatus.textContent, /sensitive|沒有已分享/);
  }
});

test("logged out, invalid session, unknown role and wrong resident never fetch", () => {
  for (const mode of ["none", "resident"]) {
    const { c, pending } = harness();
    c.authState.authMode = mode;
    c.loadMoodDiary("resident-a");
    assert.equal(pending.length, 0);
  }
  const { c, pending } = harness();
  c.loadMoodDiary("resident-b");
  c.sessionInvalid = true;
  c.loadMoodDiary("resident-a");
  assert.equal(pending.length, 0);
});

test("switching residents discards late success and late unauthorized errors", async () => {
  for (const status of [200, 401, 403]) {
    const { c, pending } = harness();
    const old = c.loadMoodDiary("resident-a");
    c.resetResidentDetail();
    c.activeElderId = "resident-b";
    const current = c.loadMoodDiary("resident-b");
    respond(pending[1], [{ sharedWithCaregiver: true, content: "resident-b-text" }]);
    await current;
    respond(pending[0], [{ sharedWithCaregiver: true, content: "resident-a-text" }], status);
    await old;
    assert.match(c.elH.diaryEntries.innerHTML, /resident-b-text/);
    assert.doesNotMatch(c.elH.diaryEntries.innerHTML, /resident-a-text/);
    assert.equal(c.sessionInvalid, false);
  }
});

test("logout, login with same identity and role change clear diary and invalidate requests", async () => {
  for (const change of [c => c.logout(), c => c.applyLogin("caregiver", "test-caregiver"),
    c => c.applyLogin("super_admin", "test-admin")]) {
    const { c, pending } = harness();
    const work = c.loadMoodDiary("resident-a");
    c.elH.diaryEntries.innerHTML = "previous";
    change(c);
    assert.equal(c.elH.diaryEntries.innerHTML, "");
    assert.ok(c.elH.elderAnalysis.classList.contains("hidden"));
    respond(pending[0], [{ sharedWithCaregiver: true, content: "late-private-text" }]);
    await work;
    assert.equal(c.elH.diaryEntries.innerHTML, "");
  }
});

test("refresh response ordering and changes during JSON parsing cannot restore stale content", async () => {
  const { c, pending } = harness();
  const old = c.loadMoodDiary("resident-a");
  const current = c.loadMoodDiary("resident-a");
  respond(pending[1], [{ sharedWithCaregiver: true, content: "latest" }]);
  await current;
  respond(pending[0], [{ sharedWithCaregiver: true, content: "outdated" }]);
  await old;
  assert.match(c.elH.diaryEntries.innerHTML, /latest/);
  assert.doesNotMatch(c.elH.diaryEntries.innerHTML, /outdated/);
  const parsing = c.loadMoodDiary("resident-a");
  let resolveBody;
  pending[2].resolve({ status: 200, ok: true, json: () => new Promise(resolve => { resolveBody = resolve; }) });
  await Promise.resolve();
  c.logout();
  resolveBody({ success: true, entries: [{ sharedWithCaregiver: true, content: "late" }] });
  await parsing;
  assert.equal(c.elH.diaryEntries.innerHTML, "");
});

test("only the current authorized detail response starts a diary request", async () => {
  const { c, pending } = harness();
  const old = c.loadElderAnalysis("resident-a");
  const current = c.loadElderAnalysis("resident-b");
  pending[1].resolve({ status: 200, ok: true, json: async () => ({ profile: {} }) });
  await current;
  assert.equal(pending[2].url, "/api/admin/residents/resident-b/mood-diary");
  pending[0].resolve({ status: 200, ok: true, json: async () => ({ profile: {} }) });
  await old;
  assert.equal(pending.length, 3);
  respond(pending[2]);
});

test("denied resident detail does not fetch diary", async () => {
  const { c, pending } = harness();
  const work = c.loadElderAnalysis("resident-a");
  respond(pending[0], [], 403);
  await work;
  assert.equal(pending.length, 1);
  assert.ok(c.elH.elderAnalysis.classList.contains("hidden"));
  assert.match(c.elH.healthStatus.textContent, /沒有權限/);
});
