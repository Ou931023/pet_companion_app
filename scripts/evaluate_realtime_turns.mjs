import { openSync, readSync, closeSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const MAX_BYTES = 65536;
const kinds = new Set(['input.started', 'input.ended', 'synthetic.continuation',
  'synthetic.backchannel', 'output_audio_buffer.started', 'output_audio_buffer.stopped', 'response.done']);
const integer = value => Number.isSafeInteger(value) && value >= 0;
const keysAre = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const invalid = () => { throw new Error('INVALID_SYNTHETIC_FIXTURE'); };

export function validateFixture(fixture) {
  if (!keysAre(fixture, ['schemaVersion', 'synthetic', 'events']) || fixture.schemaVersion !== 1
      || fixture.synthetic !== true || !Array.isArray(fixture.events) || fixture.events.length > 1000) invalid();
  let sequence = -1;
  const clocks = new Map();
  for (const event of fixture.events) {
    if (!keysAre(event, ['sequence', 'atMs', 'session', 'generation', 'turn', 'event'])
        || !['sequence', 'atMs', 'session', 'generation', 'turn'].every(key => integer(event[key]))
        || !kinds.has(event.event) || event.sequence <= sequence) invalid();
    const scope = `${event.session}:${event.generation}`;
    if (event.atMs < (clocks.get(scope) ?? 0)) invalid();
    clocks.set(scope, event.atMs);
    sequence = event.sequence;
  }
  if (Buffer.byteLength(JSON.stringify(fixture)) > MAX_BYTES) invalid();
  return fixture;
}

// This contract consumes deliberately authored fixtures, not production telemetry.
// Sequence is arrival order; clocks may restart only in a new session/generation.
export function evaluateTurns(fixture) {
  validateFixture(fixture);
  const turns = new Map();
  const closed = new Set();
  const diagnostics = [];
  let activeScope;
  for (const event of fixture.events) {
    const scope = `${event.session}:${event.generation}`;
    if (scope !== activeScope) {
      if (closed.has(scope)) {
        diagnostics.push({ sequence: event.sequence, code: 'closed_scope_event' });
        continue;
      }
      if (activeScope !== undefined) closed.add(activeScope);
      activeScope = scope;
    }
    const key = `${scope}:${event.turn}`;
    if (!turns.has(key)) turns.set(key, {
      session: event.session, generation: event.generation, turn: event.turn,
      seen: new Map(), inputEnd: null, continuationGapsMs: [], issues: [], unsupported: false,
    });
    const turn = turns.get(key);
    const issue = code => turn.issues.push({ sequence: event.sequence, code });
    if (event.event === 'synthetic.continuation') {
      if (turn.inputEnd === null) { issue('continuation_without_input_end'); continue; }
      if (turn.seen.has('output_audio_buffer.started')) issue('continuation_after_output_started');
      turn.continuationGapsMs.push(event.atMs - turn.inputEnd);
      turn.inputEnd = null;
      turn.seen.delete('input.ended');
      continue;
    }
    if (event.event === 'synthetic.backchannel') {
      turn.unsupported = true;
      issue(turn.seen.has('output_audio_buffer.started') && !turn.seen.has('output_audio_buffer.stopped')
        ? 'backchannel_unsupported_by_current_policy' : 'backchannel_outside_playback');
      continue;
    }
    if (turn.seen.has(event.event)) {
      issue(turn.seen.get(event.event).atMs === event.atMs ? 'duplicate_event' : 'conflicting_duplicate');
      continue; // Never overwrite the first event with a later duplicate.
    }
    turn.seen.set(event.event, event);
    if (event.event === 'input.started' && turn.hadInputEnd) issue('input_end_before_start');
    if (event.event === 'input.ended') {
      // Keep contradictions even if a later continuation replaces this candidate.
      turn.hadInputEnd = true;
      turn.inputEnd = event.atMs;
    }
  }
  const results = [...turns.values()].map(turn => {
    const required = ['input.started', 'input.ended', 'output_audio_buffer.started', 'output_audio_buffer.stopped'];
    const missing = required.filter(kind => !turn.seen.has(kind));
    const ordered = required.map(kind => turn.seen.get(kind));
    const outOfOrder = ordered.some((event, index) => event && ordered.slice(0, index).some(previous =>
      previous && (previous.sequence > event.sequence || previous.atMs > event.atMs)));
    if (outOfOrder) turn.issues.push({ code: 'invalid_event_order' });
    const invalidOrder = turn.issues.some(issue => !['duplicate_event', 'backchannel_unsupported_by_current_policy'].includes(issue.code));
    const status = invalidOrder ? 'invalid' : missing.length ? 'incomplete'
      : turn.unsupported ? 'unsupported_policy' : 'complete';
    return {
      session: turn.session, generation: turn.generation, turn: turn.turn, status, missing,
      inputEndToOutputStartMs: status === 'complete' ? ordered[2].atMs - ordered[1].atMs : null,
      playbackDurationMs: status === 'complete' ? ordered[3].atMs - ordered[2].atMs : null,
      generationDoneMs: turn.seen.get('response.done')?.atMs ?? null,
      playbackStoppedMs: turn.seen.get('output_audio_buffer.stopped')?.atMs ?? null,
      continuationGapsMs: turn.continuationGapsMs, issues: turn.issues,
    };
  });
  return { schemaVersion: 1, synthetic: true, policy: 'no_interruption',
    measurement: 'synthetic_ordering_only', turns: results, diagnostics,
    completeTurns: results.filter(turn => turn.status === 'complete').length };
}

export function main(args, { stdout = process.stdout, stderr = process.stderr } = {}) {
  if (args.length !== 1) { stderr.write('USAGE: node scripts/evaluate_realtime_turns.mjs fixture.json\n'); return 2; }
  let fd;
  try {
    fd = openSync(args[0], 'r');
    const buffer = Buffer.alloc(MAX_BYTES + 1);
    let size = 0;
    while (size < buffer.length) {
      const count = readSync(fd, buffer, size, buffer.length - size, null);
      if (!count) break;
      size += count;
    }
    if (size > MAX_BYTES) invalid();
    const result = evaluateTurns(JSON.parse(buffer.subarray(0, size).toString('utf8')));
    stdout.write(JSON.stringify(result, null, 2) + '\n');
    return 0; // A readable report can contain incomplete/unsupported turns.
  } catch {
    stderr.write('INVALID_SYNTHETIC_FIXTURE\n');
    return 2;
  } finally { if (fd !== undefined) closeSync(fd); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2));
}
