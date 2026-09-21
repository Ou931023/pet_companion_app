const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/app.js', 'utf8');
function harness(loaders = {}) {
  const element = () => ({ textContent: '', innerHTML: '' });
  const c = vm.createContext({
    workspaceRequestId: 0, sessionInvalid: false,
    elW: Object.fromEntries(['residentCount','alertCount','taskCount','rosterCount','roster'].map(k => [k, element()])),
    ensureCanFetch: () => true, isSuperAdminMode: () => true,
    setWorkspaceStatus: message => { c.message = message; },
    renderWorkspaceRoster: rows => { c.rows = rows; },
    handleSessionExpired: () => { c.sessionInvalid = true; c.resetWorkspace(); },
    SESSION_EXPIRED_MSG: 'expired', EMPTY_CAREGIVER_MSG: 'unassigned',
    fetchWorkspaceResidents: async () => [{ id: 'resident-1', displayName: 'Test' }],
    fetchWorkspaceAlerts: async () => ({ alerts: [] }),
    fetchWorkspaceTasks: async () => ({ tasks: [{ status: 'needs_review' }] }),
    ...loaders,
  });
  for (const name of ['resetWorkspace','normalizeWorkspaceResidents','loadWorkspace']) {
    const start = source.indexOf('  function ' + name + '(');
    vm.runInContext(source.slice(start, source.indexOf('\n  }', start) + 4), c);
  }
  return c;
}
test('workspace loads genuine counts', async () => {
  const c = harness(); await c.loadWorkspace();
  assert.equal(c.elW.residentCount.textContent, '1');
  assert.equal(c.elW.taskCount.textContent, '1');
});
test('task failure retains residents and does not invent zero tasks', async () => {
  const c = harness({ fetchWorkspaceTasks: async () => { throw Error('service_failed'); } });
  await c.loadWorkspace();
  assert.equal(c.elW.residentCount.textContent, '1');
  assert.equal(c.elW.taskCount.textContent, '—');
  assert.match(c.message, /日常任務暫時無法載入/);
});
test('expired session clears all counts and ignores later results', async () => {
  const c = harness({ fetchWorkspaceAlerts: async () => { throw Error('session_expired'); } });
  await c.loadWorkspace();
  assert.equal(c.elW.residentCount.textContent, '—');
  assert.equal(c.message, 'expired');
});
test('older refresh cannot replace latest data', async () => {
  let resolve;
  const c = harness({ fetchWorkspaceResidents: () => new Promise(r => { resolve = r; }) });
  const first = c.loadWorkspace(); await Promise.resolve();
  c.fetchWorkspaceResidents = async () => [];
  await c.loadWorkspace(); resolve([{ id: 'old' }]); await first;
  assert.equal(c.elW.residentCount.textContent, '0');
});
test('auth reset invalidates pending results', async () => {
  let resolve;
  const c = harness({ fetchWorkspaceResidents: () => new Promise(r => { resolve = r; }) });
  const request = c.loadWorkspace(); await Promise.resolve();
  c.resetWorkspace(); resolve([{ id: 'old' }]); await request;
  assert.equal(c.elW.residentCount.textContent, '—');
});
test('permission failure names affected section without hiding other sections', async () => {
  const c = harness({ fetchWorkspaceTasks: async () => { throw Error('forbidden'); } });
  await c.loadWorkspace();
  assert.match(c.message, /日常任務沒有查看權限/);
  assert.equal(c.elW.residentCount.textContent, '1');
});
test('workspace requests abort after timeout and clean up the timer', async () => {
  let expire, cleared = false;
  const c = vm.createContext({
    AbortController, authHeaders: () => ({}),
    setTimeout: (fn, delay) => { assert.equal(delay, 15000); expire = fn; return 1; },
    clearTimeout: () => { cleared = true; },
    fetch: (url, { signal }) => new Promise((resolve, reject) => {
      signal.addEventListener('abort', () => reject(Error('timeout')));
    }),
  });
  const start = source.indexOf('  function workspaceFetch(');
  vm.runInContext(source.slice(start, source.indexOf('\n  }', start) + 4), c);
  const pending = c.workspaceFetch('/api/admin/elders');
  expire(); await assert.rejects(pending, /timeout/);
  assert.equal(cleared, true);
});
test('malformed responses are failures, never empty successes', async () => {
  const c = vm.createContext({ workspaceFetch: async () => ({ success: false }),
    workspaceResidentUrl: () => '/elders', getApiBase: () => '/api', adminUrl: p => p });
  for (const name of ['fetchWorkspaceResidents', 'fetchWorkspaceAlerts', 'fetchWorkspaceTasks']) {
    const start = source.indexOf('  function ' + name + '(');
    vm.runInContext(source.slice(start, source.indexOf('\n  }', start) + 4), c);
    await assert.rejects(c[name](), /invalid_response/);
  }
});
