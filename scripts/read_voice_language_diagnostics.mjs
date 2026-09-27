import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const method = 'ext.careCompanion.voiceLanguageSnapshot';
const maxBytes = 65536;
const maxTransportBytes = 128 * 1024;
const eventCodes = new Set([
  'capture_ready', 'preference_changed', 'session_invalidated',
  'update_requested', 'applied', 'not_applied', 'final_not_command',
  'final_stale_revision', 'final_command_accepted', 'preference_save_failed',
  'next_input_started', 'response_started', 'capture_held', 'ack_timeout',
  'send', 'send_failed', 'matched', 'ignored', 'rejected', 'unknown',
  'baseline_ready', 'baseline_waiting', 'baseline_timeout',
]);
const languages = new Set(['zh-TW', 'taigi', 'mixed-zh-taigi', 'unknown']);
const failures = new Set(['none', 'timeout', 'send', 'rejected', 'preferenceSave']);
const integer = (v) => Number.isSafeInteger(v) && v >= 0;
const keysAre = (v, keys) => v && typeof v === 'object' && !Array.isArray(v)
  && Object.keys(v).length === keys.length && keys.every((key) => Object.hasOwn(v, key));
const fail = () => { throw new Error('INVALID_SNAPSHOT'); };

// Reject entire unknown schemas, never forward fields merely because they look safe.
export function validateSnapshot(value) {
  if (!keysAre(value, ['schemaVersion', 'dropped', 'events'])
      || value.schemaVersion !== 2 || !integer(value.dropped)
      || !Array.isArray(value.events) || value.events.length > 128) fail();
  let sequence = -1;
  for (const event of value.events) {
    if (!keysAre(event, ['sequence', 'elapsedMs', 'event', 'attempt', 'generation',
      'revision', 'desired', 'applied', 'pending', 'channelOpen', 'baselineReady', 'failure'])
        || !['sequence', 'elapsedMs', 'attempt', 'generation', 'revision'].every((k) => integer(event[k]))
        || event.sequence === 0 || event.sequence <= sequence || !eventCodes.has(event.event)
        || !languages.has(event.desired) || !languages.has(event.applied)
        || typeof event.pending !== 'boolean' || typeof event.channelOpen !== 'boolean'
        || typeof event.baselineReady !== 'boolean'
        || !failures.has(event.failure) || Buffer.byteLength(JSON.stringify(event)) > 512) fail();
    if ((event.event === 'baseline_timeout' && event.failure !== 'timeout')
        || (['baseline_ready', 'baseline_waiting'].includes(event.event) && event.failure !== 'none')) fail();
    sequence = event.sequence;
  }
  const text = JSON.stringify(value);
  if (Buffer.byteLength(text) > maxBytes) fail();
  return text;
}

export async function readSnapshot(uri, { Socket = WebSocket, timeoutMs = 8000, signal } = {}) {
  let url;
  try { url = new URL(uri); } catch { throw new Error('INVALID_ENDPOINT'); }
  if (url.protocol !== 'ws:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)
      || url.username || url.password || url.search || url.hash
      || !/^\/[A-Za-z0-9_-]{8,}(?:=|%3D)?\/ws$/.test(url.pathname)) throw new Error('INVALID_ENDPOINT');
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0 || timeoutMs > 15000) throw new Error('INVALID_TIMEOUT');
  if (signal?.aborted) throw new Error('CANCELLED');
  let socket;
  try { socket = new Socket(uri); } catch { throw new Error('CONNECTION_FAILED'); }
  let sequence = 0;
  const pending = new Map();
  let terminal;
  const abort = (code) => {
    terminal = code;
    for (const request of pending.values()) request.reject(new Error(code));
    pending.clear();
  };
  socket.addEventListener('message', ({ data }) => {
    if (typeof data !== 'string' || Buffer.byteLength(data) > maxTransportBytes) {
      abort('INVALID_RPC'); return;
    }
    let reply;
    try { reply = JSON.parse(data); } catch { abort('INVALID_RPC'); return; }
    const request = pending.get(reply?.id);
    if (!request) return;
    pending.delete(reply.id);
    if (reply.error) request.reject(new Error('RPC_FAILED'));
    else request.resolve(reply.result);
  });
  const rpc = (name, params = {}) => new Promise((resolve, reject) => {
    if (terminal) { reject(new Error(terminal)); return; }
    const id = ++sequence;
    pending.set(id, { resolve, reject });
    try { socket.send(JSON.stringify({ jsonrpc: '2.0', id, method: name, params })); }
    catch { pending.delete(id); reject(new Error('CONNECTION_FAILED')); }
  });
  let timer, onAbort;
  try {
    return await Promise.race([
      new Promise((_, reject) => {
        timer = setTimeout(() => { abort('RPC_TIMEOUT'); reject(new Error('RPC_TIMEOUT')); }, timeoutMs);
        onAbort = () => { abort('CANCELLED'); reject(new Error('CANCELLED')); };
        signal?.addEventListener('abort', onAbort, { once: true });
        socket.addEventListener('error', () => { abort('CONNECTION_FAILED'); reject(new Error('CONNECTION_FAILED')); });
        socket.addEventListener('close', () => { abort('CONNECTION_CLOSED'); reject(new Error('CONNECTION_CLOSED')); });
      }),
      (async () => {
        await new Promise((resolve) => socket.addEventListener('open', resolve, { once: true }));
        const vm = await rpc('getVM');
        if (!Array.isArray(vm?.isolates) || vm.isolates.length > 32) throw new Error('INVALID_RPC');
        const matches = [];
        for (const isolate of vm.isolates) {
          if (typeof isolate?.id !== 'string') throw new Error('INVALID_RPC');
          const detail = await rpc('getIsolate', { isolateId: isolate.id });
          if (Array.isArray(detail?.extensionRPCs) && detail.extensionRPCs.includes(method)) matches.push(isolate.id);
        }
        if (!matches.length) throw new Error('EXTENSION_MISSING');
        if (matches.length !== 1) throw new Error('AMBIGUOUS_TARGET');
        return validateSnapshot(await rpc(method, { isolateId: matches[0] }));
      })(),
    ]);
  } finally {
    clearTimeout(timer);
    if (onAbort) signal?.removeEventListener('abort', onAbort);
    abort('CONNECTION_CLOSED');
    try { socket.close(); } catch { /* Do not expose transport exception text. */ }
  }
}

export async function main(args = process.argv.slice(2), {
  spawnProcess = spawn, read = readSnapshot, out = console.log, error = console.error,
  installLaunch = false, attachTimeoutMs, cleanupGraceMs = 3000,
} = {}) {
  if (args.length !== 1 || !/^[A-Za-z0-9-]{8,80}$/.test(args[0])) {
    error('Usage: node scripts/read_voice_language_diagnostics.mjs DEVICE_ID');
    return 1;
  }
  const maxDeadline = installLaunch === true ? 90000 : 15000;
  attachTimeoutMs ??= maxDeadline;
  if (typeof installLaunch !== 'boolean'
      || !Number.isFinite(attachTimeoutMs) || attachTimeoutMs <= 0 || attachTimeoutMs > maxDeadline
      || !Number.isFinite(cleanupGraceMs) || cleanupGraceMs < 0 || cleanupGraceMs > 3000) {
    error('DIAGNOSTICS_UNAVAILABLE: invalid deadline'); return 1;
  }
  // Machine output and the authenticated VM URI stay in memory, never in logs/files.
  const deadline = Date.now() + attachTimeoutMs;
  let child;
  try {
    const command = installLaunch
      ? ['run', '--profile', '--use-application-binary=build/ios/iphoneos/Runner.app', '--no-pub', '--machine', '-d', args[0]]
      : ['attach', '--profile', '--machine', '--app-id', 'tw.edu.ncyu.im.aicompanion', '-d', args[0]];
    child = spawnProcess('flutter', command, { stdio: ['pipe', 'pipe', 'pipe'] });
  } catch { error('DIAGNOSTICS_UNAVAILABLE: flutter attach failed'); return 1; }
  const cancellation = new AbortController();
  return await new Promise((resolve) => {
    let buffer = '', finished = false, reading = false, killTimer, appId, childClosed = false;
    const kill = (signal) => { if (!childClosed) { try { child.kill(signal); } catch { /* Fixed boundary. */ } } };
    const stop = (status, text) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      cancellation.abort();
      if (text) (status === 0 ? out : error)(text);
      if (appId && !childClosed) {
        try { child.stdin.write(`${JSON.stringify([{ id: 1, method: 'app.detach', params: { appId } }])}\n`); }
        catch { kill('SIGINT'); }
      } else kill('SIGINT');
      if (!childClosed) killTimer = setTimeout(() => kill('SIGKILL'), cleanupGraceMs);
      resolve(status);
    };
    const timer = setTimeout(() => stop(1, 'DIAGNOSTICS_UNAVAILABLE: attach timeout'), Math.max(0, deadline - Date.now()));
    child.stdin.on?.('error', () => { kill('SIGINT'); stop(1, 'DIAGNOSTICS_UNAVAILABLE: detach failed'); });
    child.stderr.on('data', () => {});
    child.stdout.on('data', (chunk) => {
      buffer += chunk;
      if (Buffer.byteLength(buffer) > maxTransportBytes) {
        buffer = ''; stop(1, 'DIAGNOSTICS_UNAVAILABLE: oversized machine output'); return;
      }
      let newline;
      while ((newline = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        let events;
        try { events = JSON.parse(line); } catch { continue; }
        if (!Array.isArray(events)) continue;
        for (const event of events) {
          if (!event || typeof event !== 'object' || Array.isArray(event)) {
            stop(1, 'DIAGNOSTICS_UNAVAILABLE: invalid machine event'); continue;
          }
          if (finished) {
            if (event.id === 1 && (event.error || event.result === false)) kill('SIGINT');
            continue;
          }
          if (event.event === 'app.start' && typeof event.params?.appId === 'string') {
            appId = event.params.appId;
          }
          if (event.event !== 'app.debugPort' || reading) continue;
          reading = true;
          Promise.resolve().then(() => {
            const remaining = deadline - Date.now();
            if (remaining <= 0 || cancellation.signal.aborted) throw new Error('RPC_TIMEOUT');
            return read(event.params?.wsUri, {
              signal: cancellation.signal, timeoutMs: Math.min(15000, remaining),
            });
          })
            .then((snapshot) => stop(0, snapshot))
            .catch(() => stop(1, 'DIAGNOSTICS_UNAVAILABLE: snapshot rejected or unavailable'));
        }
      }
    });
    child.on('error', () => stop(1, 'DIAGNOSTICS_UNAVAILABLE: flutter attach failed'));
    child.on('close', () => { childClosed = true; stop(1, 'DIAGNOSTICS_UNAVAILABLE: attach closed'); clearTimeout(killTimer); });
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { process.exitCode = await main(); }
  catch { console.error('DIAGNOSTICS_UNAVAILABLE: reader failed'); process.exitCode = 1; }
}
