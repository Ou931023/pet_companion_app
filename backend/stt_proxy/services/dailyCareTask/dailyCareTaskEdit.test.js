const assert = require('node:assert/strict');
const { test } = require('node:test');
const express = require('express');

const { editTask, validateTaskEdit } = require('./dailyCareTaskStore');
const { registerDailyCareTaskEditRoutes } = require('./dailyCareTaskEditRoutes');

const userId = '11111111-1111-1111-1111-111111111111';
const elderId = '22222222-2222-2222-2222-222222222222';

function taskRow(overrides = {}) {
  return {
    id: 'task-1',
    elder_id: elderId,
    title: '吃藥',
    type: 'medication',
    description: '',
    scheduled_time: '08:00',
    due_at: null,
    status: 'pending',
    proof_required: true,
    created_at: new Date('2026-09-21T00:00:00Z'),
    updated_at: new Date('2026-09-21T00:00:00Z'),
    ...overrides,
  };
}

function editDb({ task = taskRow(), submissions = [], owner = true } = {}) {
  const calls = [];
  const client = {
    async query(sql, args = []) {
      calls.push({ sql, args });
      if (/SELECT id FROM users/.test(sql)) return { rows: owner ? [{ id: userId }] : [] };
      if (/SELECT \* FROM daily_care_tasks/.test(sql)) return { rows: task ? [task] : [] };
      if (/SELECT id FROM daily_care_task_submissions/.test(sql)) return { rows: submissions };
      if (/UPDATE daily_care_tasks/.test(sql)) {
        return {
          rows: [{
            ...task,
            title: args.includes('新的任務') ? '新的任務' : task.title,
            scheduled_time: args.includes('09:30') ? '09:30' : task.scheduled_time,
          }],
        };
      }
      return { rows: [] };
    },
    release() {},
  };
  return { calls, pg: { getPool: () => ({ connect: async () => client }) } };
}

test('task edit accepts only the three documented fields and validates time', () => {
  assert.deepEqual(validateTaskEdit({ title: ' 新的任務 ', scheduledTime: '09:30' }), {
    title: '新的任務',
    scheduledTime: '09:30',
  });
  for (const body of [{}, { status: 'completed' }, { title: ' ' }, { scheduledTime: '9:30' }]) {
    assert.throws(() => validateTaskEdit(body), { code: 'invalid_payload', status: 400 });
  }
});

test('resident can edit only an owned pending task without a submission', async () => {
  const { pg, calls } = editDb();
  const result = await editTask('task-1', { title: '新的任務', scheduledTime: '09:30' }, {
    pg,
    residentCaller: { userId, elderId },
  });
  assert.equal(result.title, '新的任務');
  assert.equal(result.scheduledTime, '09:30');
  assert.equal(calls[0].sql, 'BEGIN');
  assert.match(calls.find((call) => /daily_care_tasks WHERE/.test(call.sql)).sql, /elder_id = \$2/);
  assert.equal(calls.at(-1).sql, 'COMMIT');
});

test('completed/submitted tasks, ownership failures and schedule conflicts fail closed', async () => {
  const caller = { userId, elderId };
  await assert.rejects(
    () => editTask('task-1', { title: 'x' }, { pg: editDb({ owner: false }).pg, residentCaller: caller }),
    { code: 'forbidden', status: 403 },
  );
  await assert.rejects(
    () => editTask('task-1', { title: 'x' }, { pg: editDb({ task: taskRow({ status: 'completed' }) }).pg, residentCaller: caller }),
    { code: 'task_not_editable', status: 409 },
  );
  await assert.rejects(
    () => editTask('task-1', { title: 'x' }, { pg: editDb({ submissions: [{ id: 'proof-1' }] }).pg, residentCaller: caller }),
    { code: 'task_not_editable', status: 409 },
  );
  await assert.rejects(
    () => editTask('task-1', { scheduledTime: '09:30' }, {
      pg: editDb({ task: taskRow({ due_at: new Date() }) }).pg,
      residentCaller: caller,
    }),
    { code: 'task_schedule_conflict', status: 409 },
  );
});

test('task edit routes keep resident/staff identity separate and expose safe errors', async () => {
  const calls = [];
  const app = express();
  app.use(express.json());
  registerDailyCareTaskEditRoutes(app, {
    requireResidentCaller(req, _res, next) {
      req.residentCaller = { userId, elderId };
      next();
    },
    staffAuth(req, _res, next) {
      req.authContext = { role: 'super_admin' };
      next();
    },
    async editTask(id, body, options) {
      calls.push({ id, body, options });
      if (body.title === 'fail') throw Object.assign(new Error('private'), { status: 409, code: 'task_not_editable' });
      return { id, ...body };
    },
  });
  const server = await new Promise((resolve) => {
    const listener = app.listen(0, '127.0.0.1', () => resolve(listener));
  });
  const request = async (path, body) => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    return { status: response.status, cache: response.headers.get('cache-control'), body: await response.json() };
  };
  try {
    const resident = await request('/api/daily-care-tasks/task-1', { title: 'resident' });
    assert.equal(resident.status, 200);
    assert.equal(resident.cache, 'private, no-store');
    assert.deepEqual(calls[0].options, { residentCaller: { userId, elderId } });
    const staff = await request('/api/admin/daily-care-tasks/task-1', { title: 'staff' });
    assert.equal(staff.status, 200);
    assert.deepEqual(calls[1].options, { authContext: { role: 'super_admin' } });
    const rejected = await request('/api/daily-care-tasks/task-1', { title: 'fail' });
    assert.deepEqual(rejected, {
      status: 409,
      cache: 'private, no-store',
      body: { success: false, error: 'task_not_editable' },
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
