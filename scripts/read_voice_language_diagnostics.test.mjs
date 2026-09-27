import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { validateSnapshot, readSnapshot, main } from './read_voice_language_diagnostics.mjs';

const sentinel = 'PRIVATE_USER_TRANSCRIPT_AUTH_SENTINEL';
const event = () => ({ sequence: 1, elapsedMs: 0, event: 'capture_ready', attempt: 0,
  generation: 0, revision: 0, desired: 'unknown', applied: 'unknown', pending: false,
  channelOpen: false, baselineReady: false, failure: 'none' });
const snapshot = () => ({ schemaVersion: 2, dropped: 0, events: [event()] });

test('known schema round-trips, empty snapshot is not invented success', () => {
  assert.equal(validateSnapshot(snapshot()), JSON.stringify(snapshot()));
  assert.equal(validateSnapshot({ schemaVersion: 2, dropped: 0, events: [] }),
    '{"schemaVersion":2,"dropped":0,"events":[]}');
});

test('reject unknown schema, fields, enum, types, unsafe numbers, overflow', () => {
  const bad = [null, { ...snapshot(), secret: sentinel }, { ...snapshot(), schemaVersion: 1 },
    { ...snapshot(), schemaVersion: 3 },
    { ...snapshot(), dropped: -1 }, { ...snapshot(), events: Array.from({ length: 129 }, event) }];
  for (const change of [{ secret: sentinel }, { desired: sentinel }, { event: sentinel },
    { failure: sentinel }, { pending: 'true' }, { baselineReady: 'false' }, { attempt: -1 }, { sequence: 0 }, { sequence: Infinity },
    { elapsedMs: Number.MAX_SAFE_INTEGER + 1 }]) {
    bad.push({ ...snapshot(), events: [{ ...event(), ...change }] });
  }
  for (const value of bad) assert.throws(() => validateSnapshot(value), /^Error: INVALID_SNAPSHOT$/);
  const missingBaseline = event();
  delete missingBaseline.baselineReady;
  assert.throws(() => validateSnapshot({ ...snapshot(), events: [missingBaseline] }), /^Error: INVALID_SNAPSHOT$/);
  for (const sequences of [[1, 1], [2, 1]]) {
    assert.throws(() => validateSnapshot({ ...snapshot(), events: sequences.map((sequence) => ({ ...event(), sequence })) }));
  }
  assert.doesNotThrow(() => validateSnapshot({ ...snapshot(), dropped: 4, events: [{ ...event(), sequence: 5 }] }));
});

function transport(mode = 'ok') {
  const calls = [];
  let closed = false;
  class Socket extends EventTarget {
    constructor() { super(); queueMicrotask(() => this.dispatchEvent(new Event('open'))); }
    send(text) {
      const request = JSON.parse(text);
      calls.push(request.method);
      if (mode === 'timeout') return;
      if (mode === 'close') { this.dispatchEvent(new Event('close')); return; }
      if (mode === 'error') { this.dispatchEvent(new Event('error')); return; }
      let result;
      if (request.method === 'getVM') result = { isolates: mode === 'ambiguous'
        ? [{ id: 'a' }, { id: 'b' }] : [{ id: 'a' }] };
      else if (request.method === 'getIsolate') result = { extensionRPCs: mode === 'missing'
        ? [] : ['ext.careCompanion.voiceLanguageSnapshot'] };
      else result = mode === 'leak' ? { ...snapshot(), private: sentinel } : snapshot();
      let data = mode === 'malformed' ? sentinel : mode === 'oversize' ? 'x'.repeat(128 * 1024 + 1)
        : JSON.stringify(mode === 'rpcError' ? { id: request.id, error: { message: sentinel } }
          : { id: request.id, result });
      if (mode === 'boundary') data = data.padEnd(128 * 1024, ' ');
      queueMicrotask(() => this.dispatchEvent(new MessageEvent('message', { data })));
    }
    close() { closed = true; }
  }
  return { Socket, calls, isClosed: () => closed };
}

test('reader sends only discovery and read-only snapshot RPC, closes transport', async () => {
  const t = transport();
  const value = await readSnapshot('ws://127.0.0.1:9999/synthetic-auth/ws', t);
  assert.equal(value, JSON.stringify(snapshot()));
  assert.deepEqual(t.calls, ['getVM', 'getIsolate', 'ext.careCompanion.voiceLanguageSnapshot']);
  assert.equal(t.isClosed(), true);
});

test('exact 128 KiB transport limit accepts a valid padded RPC', async () => {
  const t = transport('boundary');
  assert.equal(await readSnapshot('ws://localhost:9999/synthetic-auth=/ws', t), JSON.stringify(snapshot()));
  assert.equal(t.isClosed(), true);
});

test('baseline event failure pairs are explicit, not interchangeable', () => {
  for (const code of ['baseline_ready', 'baseline_waiting', 'baseline_timeout']) {
    for (const failure of ['none', 'timeout', 'send', 'rejected', 'preferenceSave']) {
      const value = { ...snapshot(), events: [{ ...event(), event: code, failure }] };
      if (failure === (code === 'baseline_timeout' ? 'timeout' : 'none')) {
        assert.doesNotThrow(() => validateSnapshot(value));
      } else assert.throws(() => validateSnapshot(value), /^Error: INVALID_SNAPSHOT$/);
    }
  }
});

for (const mode of ['timeout', 'close', 'error', 'malformed', 'oversize', 'rpcError', 'missing', 'ambiguous', 'leak']) {
  test(`reader fails closed without private details: ${mode}`, async () => {
    const t = transport(mode);
    await assert.rejects(readSnapshot(`ws://localhost:9999/${sentinel}/ws`, { ...t, timeoutMs: 20 }),
      (error) => /^[A-Z_]+$/.test(error.message) && !error.message.includes(sentinel));
    assert.equal(t.isClosed(), true);
    assert.equal(t.calls.every((m) => ['getVM', 'getIsolate', 'ext.careCompanion.voiceLanguageSnapshot'].includes(m)), true);
  });
}

test('reject non-loopback and malformed endpoints without echoing them', async () => {
  for (const uri of [`wss://example.com/${sentinel}`, `ws://192.168.1.1/${sentinel}`, sentinel,
    'ws://127.0.0.1:9999/ws', 'ws://localhost:9999//ws', 'ws://localhost:9999/short/ws',
    `ws://localhost:9999/${sentinel}/ws?q=1`, `ws://localhost:9999/${sentinel}/ws#fragment`]) {
    await assert.rejects(readSnapshot(uri, { Socket: class { constructor() { assert.fail('must not connect'); } } }), /^Error: INVALID_ENDPOINT$/);
  }
});

for (const mode of ['success', 'privateError', 'timeout', 'closed', 'malformed']) {
  test(`CLI never echoes machine console, URI or raw exceptions: ${mode}`, async () => {
    const output = [];
    let kills = 0;
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = () => { kills++; queueMicrotask(() => child.emit('close', 0)); };
    child.stdin = { write: (text) => {
      assert.equal(JSON.parse(text)[0].method, 'app.detach');
      queueMicrotask(() => child.emit('close', 0));
    } };
    const result = await main(['synthetic-device'], {
      out: (line) => output.push(line), error: (line) => output.push(line), attachTimeoutMs: 20,
      spawnProcess: (_binary, args) => {
        assert.equal(args.includes('--machine'), true);
        queueMicrotask(() => {
          child.stderr.emit('data', sentinel);
          child.stdout.emit('data', `${sentinel}\n${JSON.stringify([{ event: 'app.log', params: { log: sentinel } }])}\n`);
          if (mode === 'closed') { child.emit('close', 1); return; }
          if (mode === 'timeout' || mode === 'malformed') return;
          child.stdout.emit('data', `${JSON.stringify([{ event: 'app.start', params: { appId: sentinel } }])}\n`);
          child.stdout.emit('data', `${JSON.stringify([{ event: 'app.debugPort', params: {
            wsUri: `ws://127.0.0.1:9999/${sentinel}/ws`,
          } }])}\n`);
        });
        return child;
      },
      read: async () => {
        if (mode === 'privateError') throw new Error(sentinel);
        return validateSnapshot(snapshot());
      },
    });
    assert.equal(result, mode === 'success' ? 0 : 1);
    assert.equal(output.join('').includes(sentinel), false);
    assert.equal(kills, ['success', 'privateError', 'closed'].includes(mode) ? 0 : 1);
  });
}

test('transport cancellation closes socket and forbids later RPC', async () => {
  const t = transport('timeout');
  const cancel = new AbortController();
  const pending = readSnapshot('ws://127.0.0.1:9999/synthetic-auth/ws', { ...t, signal: cancel.signal });
  setTimeout(() => cancel.abort(), 5);
  await assert.rejects(pending, /^Error: CANCELLED$/);
  assert.equal(t.isClosed(), true);
  assert.deepEqual(t.calls, ['getVM']);
});

test('invalid timeout cannot override production cap', async () => {
  await assert.rejects(readSnapshot('ws://localhost:9999/synthetic-auth/ws', { timeoutMs: 15001 }), /^Error: INVALID_TIMEOUT$/);
  const output = [];
  assert.equal(await main(['synthetic-device'], { attachTimeoutMs: 15001, error: (s) => output.push(s) }), 1);
  assert.deepEqual(output, ['DIAGNOSTICS_UNAVAILABLE: invalid deadline']);
  assert.equal(await main(['synthetic-device'], { installLaunch: true, attachTimeoutMs: 90001, error: () => {} }), 1);
});

test('explicit install mode uses only fixed existing binary, caps RPC and detaches', async () => {
  const child = new EventEmitter();
  child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.stdin = new EventEmitter();
  child.stdin.write = (text) => {
    assert.equal(JSON.parse(text)[0].method, 'app.detach');
    queueMicrotask(() => child.emit('close', 0));
  };
  child.kill = () => assert.fail('graceful detach expected');
  const status = await main(['synthetic-device'], {
    installLaunch: true, out: () => {}, error: () => {},
    spawnProcess: (binary, args) => {
      assert.equal(binary, 'flutter');
      assert.deepEqual(args, ['run', '--profile', '--use-application-binary=build/ios/iphoneos/Runner.app',
        '--no-pub', '--machine', '-d', 'synthetic-device']);
      queueMicrotask(() => child.stdout.emit('data', `${JSON.stringify([
        { event: 'app.start', params: { appId: sentinel } },
        { event: 'app.debugPort', params: { wsUri: `ws://localhost:9999/${sentinel}/ws` } },
      ])}\n`));
      return child;
    },
    read: async (_uri, { timeoutMs }) => { assert.equal(timeoutMs, 15000); return validateSnapshot(snapshot()); },
  });
  assert.equal(status, 0);
});

test('synchronous spawn exception is sanitized', async () => {
  const output = [];
  const code = await main(['synthetic-device'], { spawnProcess: () => { throw new Error(sentinel); }, error: (s) => output.push(s) });
  assert.equal(code, 1);
  assert.equal(output.join('').includes(sentinel), false);
});

for (const mode of ['null', 'primitive', 'syncRead', 'writeThrow', 'stdinError', 'detachError', 'detachTimeout', 'oversize', 'deadline']) {
  test(`machine boundary and teardown: ${mode}`, async () => {
    const output = [], kills = [], writes = [];
    let readSignal, readBudget;
    const child = new EventEmitter();
    child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.stdin = new EventEmitter();
    child.kill = (signal) => { kills.push(signal); queueMicrotask(() => child.emit('close', 0)); };
    child.stdin.write = (text) => {
      writes.push(JSON.parse(text)[0].method);
      if (mode === 'writeThrow') throw new Error(sentinel);
      queueMicrotask(() => {
        if (mode === 'stdinError') child.stdin.emit('error', new Error(sentinel));
        else if (mode === 'detachError') child.stdout.emit('data', `${JSON.stringify([{ id: 1, error: sentinel }])}\n`);
        else if (mode !== 'detachTimeout') child.emit('close', 0);
      });
    };
    const status = await main(['synthetic-device'], {
      attachTimeoutMs: 30, cleanupGraceMs: 5, out: (s) => output.push(s), error: (s) => output.push(s),
      spawnProcess: () => {
        setTimeout(() => {
          if (mode === 'oversize') { child.stdout.emit('data', 'x'.repeat(128 * 1024 + 1)); return; }
          if (mode === 'null' || mode === 'primitive') {
            child.stdout.emit('data', `${JSON.stringify([mode === 'null' ? null : sentinel])}\n`); return;
          }
          child.stdout.emit('data', `${JSON.stringify([{ event: 'app.start', params: { appId: sentinel } },
            { event: 'app.debugPort', params: { wsUri: `ws://localhost:9999/${sentinel}/ws` } }])}\n`);
        }, 5);
        return child;
      },
      read: (_uri, options) => {
        readSignal = options.signal; readBudget = options.timeoutMs;
        if (mode === 'syncRead') throw new Error(sentinel);
        if (mode === 'deadline') return new Promise((_, reject) => options.signal.addEventListener('abort', () => reject(new Error(sentinel))));
        return Promise.resolve(validateSnapshot(snapshot()));
      },
    });
    await new Promise((resolve) => setTimeout(resolve, 15));
    assert.equal(output.join('').includes(sentinel), false);
    assert.equal(writes.every((method) => method === 'app.detach'), true);
    if (readSignal) { assert.equal(readSignal.aborted, true); assert.ok(readBudget <= 30 && readBudget > 0); }
    if (['null', 'primitive', 'syncRead', 'oversize', 'deadline'].includes(mode)) assert.equal(status, 1);
    if (mode === 'detachTimeout') assert.deepEqual(kills, ['SIGKILL']);
    if (['writeThrow', 'stdinError', 'detachError'].includes(mode)) assert.equal(kills.includes('SIGINT'), true);
  });
}
