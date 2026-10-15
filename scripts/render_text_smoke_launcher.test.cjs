'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, mkdtempSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const doc = readFileSync(resolve(__dirname, '../docs/RENDER_TEXT_SMOKE.md'), 'utf8');
const launcher = doc.match(/<!-- live-launcher -->\s*```bash\n([\s\S]*?)\n```/)[1];

for (const scenario of ['success', 'failure', 'timeout']) {
  for (const errexit of [false, true]) {
    test(`documented Bash launcher ${scenario}, errexit=${errexit}`, { skip: process.platform !== 'linux' }, () => {
      const dir = mkdtempSync(join(tmpdir(), 'smoke-launcher-'));
      try {
        // These executables cannot load the app/SDK or make a network request.
        writeFileSync(join(dir, 'node'), `#!/bin/bash\n[ -z "\${NODE_TLS_REJECT_UNAUTHORIZED+x}" ] || exit 91\ncat >/dev/null\n${scenario === 'timeout' ? '/bin/sleep 2' : `exit ${scenario === 'failure' ? 7 : 0}`}\n`, { mode: 0o700 });
        writeFileSync(join(dir, 'timeout'), '#!/bin/bash\n[ "$1" = "--signal=TERM" ] && [ "$2" = "--kill-after=2s" ] && [ "$3" = "65s" ] || exit 92\nshift 3\nexec /usr/bin/timeout --signal=TERM --kill-after=2s 0.2s "$@"\n', { mode: 0o700 });
        const source = 'offline synthetic source';
        const sha = createHash('sha256').update(source).digest('hex');
        const setup = `probe_source='${source}'\nexpected_probe_sha=${sha}\n`;
        // EXIT trap checks cleanup even with errexit and propagates the original status.
        const trap = `trap 'saved=$?; if [ "\${probe_source+x}" = x ]; then exit 93; fi; exit "$saved"' EXIT\n`;
        const result = spawnSync('/bin/bash', ['--noprofile', '--norc'], {
          input: `${setup}${trap}${errexit ? 'set -e\n' : ''}${launcher}\n`, encoding: 'utf8', timeout: 5000,
          env: { PATH: `${dir}:/usr/bin:/bin`, NODE_TLS_REJECT_UNAUTHORIZED: '0' },
        });
        const expected = scenario === 'success' ? 0 : scenario === 'failure' ? 7 : 124;
        assert.equal(result.error, undefined);
        assert.equal(result.status, expected, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout), { launcherExitCode: expected });
        assert.equal(result.stderr, '');
      } finally { rmSync(dir, { recursive: true, force: true }); }
    });
  }
}
