"use strict";

const { spawnSync } = require("node:child_process");
const path = require("node:path");

// Keep the original backend discovery root and test environment on every OS.
function runTests(args = process.argv.slice(2), spawn = spawnSync) {
  const result = spawn(process.execPath, ["--test", ...args], {
    cwd: path.resolve(__dirname, "../.."),
    env: {
      ...process.env,
      APP_ENV: "test",
      NODE_ENV: "test",
      OPENAI_API_KEY: "test-placeholder",
    },
    stdio: "inherit",
    shell: false,
  });
  // A spawn error or signal must not turn an incomplete run into a pass.
  return result.error || result.signal || result.status == null ? 1 : result.status;
}

if (require.main === module) process.exitCode = runTests();
module.exports = { runTests };
