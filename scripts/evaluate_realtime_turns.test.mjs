import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { evaluateTurns, validateFixture, main } from './evaluate_realtime_turns.mjs';

const fixture = entries => ({ schemaVersion: 1, synthetic: true,
  events: entries.map(([event, atMs, scope = {}], index) => ({ sequence: index + 1,
    atMs, session: 1, generation: 0, turn: 1, ...scope, event })) });
const normal = () => fixture([['input.started', 0], ['input.ended', 1000],
  ['output_audio_buffer.started', 1300], ['response.done', 1500], ['output_audio_buffer.stopped', 2000]]);

test('input end to buffer start and playback duration use separate endpoints', () => {
  const report = evaluateTurns(normal());
  assert.equal(report.measurement, 'synthetic_ordering_only');
  assert.equal(report.completeTurns, 1);
  assert.equal(report.turns[0].inputEndToOutputStartMs, 300);
  assert.equal(report.turns[0].playbackDurationMs, 700);
  assert.equal(report.turns[0].generationDoneMs, 1500);
  assert.equal(report.turns[0].playbackStoppedMs, 2000);
});

test('explicit continuation supersedes an earlier end; long silence alone cannot label continuation', () => {
  const labelled = fixture([['input.started', 0], ['input.ended', 500], ['synthetic.continuation', 2500],
    ['input.ended', 3000], ['output_audio_buffer.started', 3300], ['output_audio_buffer.stopped', 4000]]);
  const turn = evaluateTurns(labelled).turns[0];
  assert.equal(turn.status, 'complete');
  assert.equal(turn.inputEndToOutputStartMs, 300);
  assert.deepEqual(turn.continuationGapsMs, [2000]);
  const unlabelled = evaluateTurns(fixture([['input.started', 0], ['input.ended', 500],
    ['output_audio_buffer.started', 3300], ['output_audio_buffer.stopped', 4000]])).turns[0];
  assert.deepEqual(unlabelled.continuationGapsMs, []);
  assert.equal(unlabelled.inputEndToOutputStartMs, 2800);
});

test('continuation after output started is invalid, never a negative latency', () => {
  const result = evaluateTurns(fixture([['input.started', 0], ['input.ended', 500],
    ['output_audio_buffer.started', 600], ['synthetic.continuation', 2500],
    ['input.ended', 3000], ['output_audio_buffer.stopped', 4000]])).turns[0];
  assert.equal(result.status, 'invalid');
  assert.equal(result.inputEndToOutputStartMs, null);
  assert.ok(result.issues.some(issue => issue.code === 'continuation_after_output_started'));
});

for (const middle of [[['synthetic.continuation', 100], ['input.started', 200]],
  [['input.started', 100], ['synthetic.continuation', 200]]]) {
  test(`continuation cannot erase end-before-start contradiction: ${middle[0][0]}`, () => {
    const turn = evaluateTurns(fixture([['input.ended', 0], ...middle, ['input.ended', 300],
      ['output_audio_buffer.started', 400], ['output_audio_buffer.stopped', 500]])).turns[0];
    assert.equal(turn.status, 'invalid');
    assert.equal(turn.inputEndToOutputStartMs, null);
    assert.ok(turn.issues.some(issue => issue.code === 'input_end_before_start'));
  });
}

test('playback backchannel is unsupported by current policy and excluded from measured turns', () => {
  const result = evaluateTurns(fixture([['input.started', 0], ['input.ended', 100],
    ['output_audio_buffer.started', 300], ['synthetic.backchannel', 400], ['output_audio_buffer.stopped', 600]]));
  assert.equal(result.turns[0].status, 'unsupported_policy');
  assert.equal(result.turns[0].inputEndToOutputStartMs, null);
  assert.equal(result.completeTurns, 0);
});

test('generation done does not complete playback; missing endpoints stay explicit', () => {
  const input = normal(); input.events.pop();
  const turn = evaluateTurns(input).turns[0];
  assert.equal(turn.status, 'incomplete');
  assert.deepEqual(turn.missing, ['output_audio_buffer.stopped']);
  assert.equal(turn.playbackStoppedMs, null);
  assert.equal(turn.inputEndToOutputStartMs, null);
  for (const kind of ['input.started', 'input.ended', 'output_audio_buffer.started']) {
    const value = normal(); value.events = value.events.filter(event => event.event !== kind);
    assert.equal(evaluateTurns(value).turns[0].status, 'incomplete');
    assert.equal(evaluateTurns(value).turns[0].inputEndToOutputStartMs, null);
  }
});

test('duplicates are reported, first value retained; conflicting duplicates invalidate measurements', () => {
  for (const duplicateMs of [1300, 1350]) {
    const turn = evaluateTurns(fixture([['input.started', 0], ['input.ended', 1000],
      ['output_audio_buffer.started', 1300], ['output_audio_buffer.started', duplicateMs],
      ['output_audio_buffer.stopped', 2000]])).turns[0];
    assert.equal(turn.status, duplicateMs === 1300 ? 'complete' : 'invalid');
    assert.equal(turn.inputEndToOutputStartMs, duplicateMs === 1300 ? 300 : null);
    assert.equal(turn.issues[0].code, duplicateMs === 1300 ? 'duplicate_event' : 'conflicting_duplicate');
  }
});

for (const boundary of [{ session: 2 }, { generation: 1 }, { turn: 2 }]) {
  test(`no endpoint pairing across ${Object.keys(boundary)[0]}`, () => {
    const report = evaluateTurns(fixture([['input.started', 0], ['input.ended', 100],
      ['output_audio_buffer.started', 200, boundary], ['output_audio_buffer.stopped', 400, boundary]]));
    assert.equal(report.turns.length, 2);
    assert.ok(report.turns.every(turn => turn.status === 'incomplete' && turn.inputEndToOutputStartMs === null));
  });
}

test('late events from a closed generation cannot complete an earlier turn', () => {
  const report = evaluateTurns(fixture([['input.started', 0], ['input.ended', 100],
    ['input.started', 0, { generation: 1 }], ['output_audio_buffer.started', 200], ['output_audio_buffer.stopped', 400]]));
  assert.equal(report.completeTurns, 0);
  assert.equal(report.diagnostics.length, 2);
  assert.ok(report.diagnostics.every(issue => issue.code === 'closed_scope_event'));
});

test('invalid ordering is not repaired by sorting', () => {
  const report = evaluateTurns(fixture([['input.ended', 0], ['input.started', 100],
    ['output_audio_buffer.started', 200], ['output_audio_buffer.stopped', 300]]));
  assert.equal(report.turns[0].status, 'invalid');
  for (const change of [{ sequence: 0 }, { atMs: -1 }, { atMs: NaN }, { session: Infinity },
    { turn: Number.MAX_SAFE_INTEGER + 1 }, { generation: 0.5 }, { event: 'unapproved' }, { transcript: 'PRIVATE_SENTINEL' }]) {
    const value = normal(); Object.assign(value.events[1], change);
    assert.throws(() => validateFixture(value), /^Error: INVALID_SYNTHETIC_FIXTURE$/);
  }
  const clock = normal(); clock.events[2].atMs = 500;
  assert.throws(() => validateFixture(clock), /INVALID_SYNTHETIC_FIXTURE/);
  for (const value of [{ ...normal(), synthetic: false }, { ...normal(), audio: 'PRIVATE_SENTINEL' },
    { ...normal(), schemaVersion: 2 }, { ...normal(), events: Array(1001).fill(normal().events[0]) }]) {
    assert.throws(() => validateFixture(value), /INVALID_SYNTHETIC_FIXTURE/);
  }
});

test('committed synthetic cases stay reproducible', () => {
  const value = JSON.parse(readFileSync(new URL('./fixtures/realtime_turns.synthetic.json', import.meta.url), 'utf8'));
  const report = evaluateTurns(value);
  assert.deepEqual(report.turns.map(turn => turn.status), ['complete', 'complete', 'unsupported_policy',
    'incomplete', 'complete', 'incomplete', 'incomplete']);
  assert.deepEqual(report.turns.slice(0, 2).map(turn => turn.inputEndToOutputStartMs), [300, 300]);
  assert.equal(report.diagnostics.length, 1);
});

test('CLI is bounded and does not echo unknown content or paths; empty fixture yields zero evidence', () => {
  const dir = mkdtempSync(join(tmpdir(), 'synthetic-turn-eval-'));
  let out = '', err = '';
  const io = { stdout: { write: text => { out += text; } }, stderr: { write: text => { err += text; } } };
  try {
    const path = join(dir, 'fixture.json');
    writeFileSync(path, JSON.stringify({ schemaVersion: 1, synthetic: true, events: [] }));
    assert.equal(main([path], io), 0);
    assert.equal(JSON.parse(out).completeTurns, 0);
    for (const content of ['PRIVATE_SENTINEL', ' '.repeat(65537)]) {
      out = ''; err = ''; writeFileSync(path, content);
      assert.equal(main([path], io), 2);
      assert.equal(out, ''); assert.equal(err, 'INVALID_SYNTHETIC_FIXTURE\n');
    }
    assert.equal(main([join(dir, 'PRIVATE_SENTINEL')], io), 2);
    assert.ok(!err.includes('PRIVATE_SENTINEL'));
    assert.equal(main([], io), 2);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
