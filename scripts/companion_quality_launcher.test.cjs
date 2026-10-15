'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, mkdtempSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { spawnSync } = require('node:child_process');
const launcher = readFileSync(resolve(__dirname, 'run_companion_quality.sh'), 'utf8').replace(/\r\n/g, '\n');
const runner = readFileSync(resolve(__dirname, 'companion_quality.cjs'), 'utf8').replace(/\r\n/g, '\n');
test('documentation contains the exact default-dry-run launcher', () => {
  const doc = readFileSync(resolve(__dirname, '../docs/COMPANION_QUALITY_RUNNER.md'), 'utf8').replace(/\r\n/g, '\n');
  assert.ok(doc.includes('```bash\n' + launcher + '```'));
});
for (const scenario of ['dry-run', 'success', 'failure', 'timeout', 'http-error', 'hash-mismatch', 'oversize', 'download-timeout']) {
  for (const errexit of [false, true]) {
    test(`pinned launcher ${scenario}, errexit=${errexit}`, { skip: process.platform !== 'linux' }, () => {
      const dir = mkdtempSync(join(tmpdir(), 'quality-launcher-'));
      try {
        writeFileSync(join(dir, 'runner'), runner);
        const corrupt = scenario === 'hash-mismatch' ? 'echo altered' : scenario === 'oversize' ? "head -c 131073 /dev/zero | tr '\\0' x" : 'cat "$FIXTURE_SOURCE"';
        writeFileSync(join(dir, 'curl'), '#!/bin/bash\n' +
          '[ "$1" = "--disable" ] && [[ "$*" == *"--max-filesize 131072"* ]] && [[ "$*" == *"--max-time 10"* ]] && [[ "$*" == *"--max-redirs 0"* ]] && [[ "$*" == *"--proto =https"* ]] || exit 94\n' +
          '[ "${!#}" = "https://raw.githubusercontent.com/Ou931023/pet_companion_app/d7c7dd3c1fedb7a7575c9e13502549ba8d30770d/scripts/companion_quality.cjs" ] || exit 94\n' +
          (scenario === 'http-error' ? 'exit 22' : scenario === 'download-timeout' ? 'exit 28' : corrupt) + '\n', { mode: 0o700 });
        writeFileSync(join(dir, 'node'), '#!/bin/bash\n' +
          '[ -z "${NODE_TLS_REJECT_UNAUTHORIZED+x}" ] && [ -z "${NODE_OPTIONS+x}" ] && [ -z "${NODE_DEBUG+x}" ] || exit 91\n' +
          `[[ "$*" == *"${scenario === 'dry-run' ? '--dry-run' : '--execute --standard-pricing-reviewed-2026-10-15 --prior-charge-and-overall-budget-reviewed'}"* ]] || exit 95\n` +
          'cat >/dev/null\nprintf invoked > "$INVOKED"\n' + (scenario === 'timeout' ? '/bin/sleep 2' : `exit ${scenario === 'failure' ? 7 : 0}`) + '\n', { mode: 0o700 });
        writeFileSync(join(dir, 'timeout'), '#!/bin/bash\n[ "$1" = "--signal=TERM" ] && [ "$2" = "--kill-after=2s" ] && [ "$3" = "95s" ] || exit 92\nshift 3\nexec /usr/bin/timeout --signal=TERM --kill-after=2s 0.2s "$@"\n', { mode: 0o700 });
        const input = `${errexit ? 'set -e\n' : ''}trap 's=$?; [ -z "\${quality_source+x}" ] && [ -z "\${quality_sha+x}" ] || exit 93; exit "$s"' EXIT\n` +
          (scenario === 'dry-run' ? launcher : launcher.replace(/quality_once --dry-run\n$/, 'quality_once --execute\n'));
        const result = spawnSync('/bin/bash', ['--noprofile', '--norc'], { input, encoding: 'utf8', timeout: 5000,
          env: { PATH: `${dir}:/usr/bin:/bin`, FIXTURE_SOURCE: join(dir, 'runner'), INVOKED: join(dir, 'invoked'),
            NODE_TLS_REJECT_UNAUTHORIZED: '0', NODE_OPTIONS: 'synthetic-preload', NODE_DEBUG: 'synthetic-debug' } });
        const early = ['http-error', 'hash-mismatch', 'oversize', 'download-timeout'].includes(scenario);
        const expected = early ? 2 : scenario === 'failure' ? 7 : scenario === 'timeout' ? 124 : 0;
        assert.equal(result.error, undefined); assert.equal(result.status, expected, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout), { launcherExitCode: expected }); assert.equal(result.stderr, '');
        if (early) assert.throws(() => readFileSync(join(dir, 'invoked')));
        else assert.equal(readFileSync(join(dir, 'invoked'), 'utf8'), 'invoked');
      } finally { rmSync(dir, { recursive: true, force: true }); }
    });
  }
}
