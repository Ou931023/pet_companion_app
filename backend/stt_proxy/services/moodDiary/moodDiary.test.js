const assert = require('node:assert/strict');
const { test, after } = require('node:test');
// Never load workstation credentials, even through transitive legacy imports.
require('dotenv').config = () => ({ parsed: {} });
const express = require('express');
const { createStore, validateCreate, validateShare, listLimit } = require('./moodDiaryStore');
const { registerMoodDiaryRoutes } = require('./moodDiaryRoutes');
const residentAuth = require('../auth/residentCallerContext');
const staffAuth = require('../admin/adminAuthContext');
const authz = require('../admin/authorizationService');

const elder = '11111111-1111-1111-1111-111111111111';
const other = '22222222-2222-2222-2222-222222222222';
const user = '33333333-3333-3333-3333-333333333333';
const staff = '44444444-4444-4444-4444-444444444444';
const caller = { userId: user, elderId: elder };

function fixture() {
  const state = { rows: [], calls: [], assigned: true, active: true, role: 'elder', down: false };
  const pg = {
    isPostgresAvailable: async () => true,
    async query(sql, args = []) {
      state.calls.push({ sql, args });
      if (state.down) throw new Error('private database error');
      if (sql.includes('firebase_uid')) {
        const uid = args[0];
        if (uid === 'resident') return { rows: [{ id: user, elder_id: elder, role: state.role, status: state.active ? 'active' : 'inactive' }] };
        if (uid === 'other') return { rows: [{ id: other, elder_id: other, role: 'elder', status: 'active' }] };
        return { rows: [{ id: staff, role: uid === 'admin' ? 'super_admin' : 'caregiver', status: 'active' }] };
      }
      if (sql.startsWith('SELECT id FROM users')) return { rows: state.role === 'elder' && state.active ? [{ id: args[0] }] : [] };
      if (sql.startsWith('SELECT elder_id FROM resident_caregiver_links')) return { rows: state.assigned ? [{ elder_id: elder }] : [] };
      if (sql.includes('INSERT INTO mood_diary_entries')) {
        const row = { id: args[0], user_id: args[1], elder_id: args[2], mood: args[3], content: args[4], shared_with_caregiver: args[5], created_at: new Date() };
        state.rows.push(row);
        return { rows: [row] };
      }
      if (sql.startsWith('SELECT d.*')) {
        assert.match(sql, /shared_with_caregiver = TRUE/);
        assert.match(sql, /l.status = 'active'/);
        return { rows: state.rows.filter((r) => r.elder_id === args[0] && r.shared_with_caregiver && (args[2] || state.assigned)).slice(0, args[1]) };
      }
      if (sql.startsWith('SELECT * FROM mood_diary_entries')) {
        return { rows: state.rows.filter((r) => r.user_id === args[0] && r.elder_id === args[1]).slice(0, args[2]) };
      }
      const row = state.rows.find((r) => r.id === args[0] && r.user_id === args[1] && r.elder_id === args[2]);
      assert.match(sql, /id = \$1 AND user_id = \$2 AND elder_id = \$3/);
      if (row && sql.startsWith('UPDATE')) row.shared_with_caregiver = args[3];
      if (row && sql.startsWith('DELETE')) state.rows.splice(state.rows.indexOf(row), 1);
      return { rows: row ? [row] : [] };
    },
  };
  return { state, pg, store: createStore(pg) };
}

test('diary input whitelist, strict boolean, code-point length and limit validation', () => {
  assert.equal(validateCreate({ mood: 'okay', content: '  hello  ' }).sharedWithCaregiver, false);
  assert.equal(validateCreate({ mood: 'low', content: 'x'.repeat(1000) }).content.length, 1000);
  assert.doesNotThrow(() => validateCreate({ mood: 'happy', content: '\u{1f642}'.repeat(1000) }));
  for (const body of [null, [], {}, { mood: 'bad', content: 'x' }, { mood: 'low', content: ' ' },
    { mood: 'low', content: 'x'.repeat(1001) }, { mood: 'low', content: 'x', elderId: elder },
    { mood: 'low', content: 'x', sharedWithCaregiver: 'true' }, { mood: 'low', content: 'x', transcript: 'private' }]) {
    assert.throws(() => validateCreate(body), { code: 'invalid_payload' });
  }
  assert.equal(validateShare({ sharedWithCaregiver: false }), false);
  assert.throws(() => validateShare({ sharedWithCaregiver: true, mood: 'low' }));
  assert.equal(listLimit(undefined), 50);
  assert.equal(listLimit('100'), 100);
  for (const value of ['0', '101', '1.5', '-1', ['1'], '1e1']) assert.throws(() => listLimit(value));
});

test('own create/list, private default, shared-only even admin, immediate revoke and deletion', async () => {
  const { store, state } = fixture();
  const created = await store.create(caller, { mood: 'happy', content: '<script>plain text</script>' });
  assert.deepEqual(Object.keys(created), ['id', 'mood', 'content', 'createdAt', 'sharedWithCaregiver']);
  assert.equal(created.sharedWithCaregiver, false);
  assert.equal((await store.list(caller, 50)).length, 1);
  assert.deepEqual(await store.listShared(elder, { role: 'super_admin' }, 50), []);
  await store.share(caller, created.id, { sharedWithCaregiver: true });
  assert.equal((await store.listShared(elder, { role: 'caregiver', caregiverId: staff }, 50)).length, 1);
  const revoked = await store.share(caller, created.id, { sharedWithCaregiver: false });
  assert.equal(revoked.sharedWithCaregiver, false);
  assert.equal(revoked.content, created.content);
  assert.deepEqual(await store.listShared(elder, { role: 'super_admin' }, 50), []);
  await store.remove(caller, created.id);
  assert.equal(state.rows.length, 0);
  await assert.rejects(() => store.remove(caller, created.id), { code: 'not_found' });
});

test('cross-owner mutations cannot read, share or delete another account entry', async () => {
  const { store } = fixture();
  const created = await store.create(caller, { mood: 'okay', content: 'private' });
  const stranger = { userId: other, elderId: elder };
  assert.deepEqual(await store.list(stranger, 50), []);
  await assert.rejects(() => store.share(stranger, created.id, { sharedWithCaregiver: true }), { code: 'not_found' });
  await assert.rejects(() => store.remove(stranger, created.id), { code: 'not_found' });
  assert.equal((await store.list(caller, 50)).length, 1);
});

test('strict elder role, inactive and mock/unlinked caller fail closed; DB errors do not fallback', async () => {
  const { store, state } = fixture();
  state.role = 'caregiver';
  await assert.rejects(() => store.list(caller, 50), { code: 'forbidden' });
  state.role = 'elder'; state.active = false;
  await assert.rejects(() => store.list(caller, 50), { code: 'forbidden' });
  await assert.rejects(() => store.list({ userId: null, elderId: elder }, 50), { code: 'forbidden' });
  state.down = true;
  await assert.rejects(() => store.list(caller, 50), /private database error/);
});

test('HTTP real auth middleware: resident ownership, staff assignment, sharing and safe errors', async () => {
  const { pg, store, state } = fixture();
  const firebase = { isConfigured: () => true, verifyIdToken: async (token) => ['resident', 'other', 'viewer', 'admin'].includes(token) ? { uid: token } : null };
  residentAuth.setFirebaseAdminForTest(firebase); residentAuth.setPgForTest(pg);
  staffAuth.setFirebaseAdminForTest(firebase); staffAuth.setPgForTest(pg); authz.setPgForTest(pg);
  const app = express(); app.use(express.json());
  registerMoodDiaryRoutes(app, { requireResidentCaller: residentAuth.requireResidentCaller, staffAuth: staffAuth.resolveDailyCareAdminAuthContext, authz, store });
  const server = await new Promise((resolve) => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
  const request = async (path, token, method = 'GET', body) => {
    const result = await fetch(`http://127.0.0.1:${server.address().port}${path}`, {
      method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    assert.equal(result.headers.get('cache-control'), 'private, no-store');
    return { status: result.status, body: await result.json() };
  };
  try {
    assert.equal((await request('/api/mood-diary')).status, 401);
    assert.equal((await request('/api/mood-diary', 'invalid')).status, 401);
    const created = await request('/api/mood-diary', 'resident', 'POST', { mood: 'worried', content: 'hello' });
    assert.equal(created.status, 201);
    const id = created.body.entry.id;
    const adminPath = `/api/admin/residents/${elder}/mood-diary`;
    assert.deepEqual((await request(adminPath, 'admin')).body.entries, []);
    assert.equal((await request(`/api/mood-diary/${id}`, 'other', 'DELETE')).status, 404);
    assert.equal((await request(`/api/mood-diary/${id}`, 'resident', 'PATCH', { sharedWithCaregiver: true })).status, 200);
    assert.equal((await request(adminPath, 'viewer')).body.entries.length, 1);
    state.assigned = false;
    assert.equal((await request(adminPath, 'viewer')).status, 403);
    assert.equal((await request(adminPath, 'admin')).body.entries.length, 1);
    await request(`/api/mood-diary/${id}`, 'resident', 'PATCH', { sharedWithCaregiver: false });
    assert.deepEqual((await request(adminPath, 'admin')).body.entries, []);
    assert.equal((await request('/api/mood-diary?limit=101', 'resident')).status, 400);
    state.role = 'caregiver';
    assert.equal((await request('/api/mood-diary', 'resident')).status, 403);
    state.role = 'elder';
    const brokenApp = express(); brokenApp.use(express.json());
    // A storage outage must be distinguishable from a successful empty diary.
    const originalList = store.list; store.list = async () => { throw new Error('private detail'); };
    const unavailable = await request('/api/mood-diary', 'resident');
    assert.deepEqual(unavailable, { status: 503, body: { success: false, error: 'diary_unavailable' } });
    store.list = originalList;
    assert.equal((await request(`/api/mood-diary/${id}`, 'resident', 'DELETE')).status, 200);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    residentAuth.setFirebaseAdminForTest(null); residentAuth.setPgForTest(null);
    staffAuth.setFirebaseAdminForTest(null); staffAuth.setPgForTest(null); authz.setPgForTest(null);
  }
});
