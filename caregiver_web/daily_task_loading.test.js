const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/app.js', 'utf8');
function load(c, names) {
  for (const name of names) {
    const start = source.indexOf('  function ' + name + '(');
    vm.runInContext(source.slice(start, source.indexOf('\n  }', start) + 4), c);
  }
}
function harness() {
  const c = vm.createContext({
    dailyTaskRequestId: 0, sessionInvalid: false,
    elT: { tasksStatus: { textContent: '' } },
    ensureCanFetch: () => true, isCaregiverMode: () => false,
    adminUrl: p => p, renderDailyTasks: rows => { c.rows = rows; },
    workspaceFetch: async () => ({ tasks: [{ elderId: 'a', status: 'pending' }] }),
    fetchWorkspaceResidents: async () => [{ id: 'a', displayName: '王奶奶' }],
  });
  load(c, ['clearDailyTaskStats','normalizeWorkspaceResidents','loadDailyTasks']);
  return c;
}
test('task list resolves names from authorized resident list', async () => {
  const c = harness(); await c.loadDailyTasks();
  assert.equal(c.rows[0].elderDisplayName, '王奶奶');
});
test('resident endpoint failure does not erase valid tasks', async () => {
  const c = harness(); c.fetchWorkspaceResidents = async () => { throw Error('service_failed'); };
  await c.loadDailyTasks(); assert.equal(c.rows.length, 1);
  assert.equal(c.rows[0].elderDisplayName, '');
});
test('late task response after auth reset is discarded', async () => {
  const c = harness(); let resolve;
  c.workspaceFetch = () => new Promise(r => { resolve = r; });
  const pending = c.loadDailyTasks(); c.clearDailyTaskStats();
  resolve({ tasks: [{ elderId: 'a' }] }); await pending;
  assert.equal(c.rows, undefined);
});
test('unsubmitted task does not show empty AI judgement or internal ID', () => {
  const c = vm.createContext({
    dailyTaskVerificationLabel: () => '', dailyTaskDetectedObjectsLabel: () => '',
    dailyTaskReviewLabel: () => '', dailyTaskVerificationClass: () => '',
    dailyTaskTypeLabel: () => '喝水', dailyTaskStatusLabel: () => '待完成',
  });
  load(c, ['escapeHtml','renderDailyTaskRow']);
  const html = c.renderDailyTaskRow({ elderId: 'internal-id', elderDisplayName: '王奶奶', status: 'pending' });
  assert.match(html, /王奶奶/); assert.match(html, /尚未送出照片/);
  assert.doesNotMatch(html, /internal-id|AI 判斷|信心/);
});
