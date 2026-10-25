"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const path = require("node:path");
const { runTests } = require("../scripts/run-tests.cjs");

test("portable test entry preserves discovery, forwards arguments without a shell and overrides test environment", () => {
  const names = ["APP_ENV", "NODE_ENV", "OPENAI_API_KEY", "RUNNER_CONTRACT_SENTINEL"];
  const original = Object.fromEntries(names.map(name => [name, process.env[name]]));
  try {
    for (const name of names) process.env[name] = "synthetic-parent-value";
    const args = ["--test-name-pattern=space and $literal", "synthetic.test.js"];
    let calls = 0;
    assert.equal(runTests(args, (executable, actualArgs, options) => {
      calls++;
      assert.equal(executable, process.execPath);
      assert.deepEqual(actualArgs, ["--test", ...args]);
      assert.equal(options.cwd, path.resolve(__dirname, "../.."));
      assert.equal(options.shell, false);
      assert.equal(options.stdio, "inherit");
      assert.equal(options.env.APP_ENV, "test");
      assert.equal(options.env.NODE_ENV, "test");
      assert.equal(options.env.OPENAI_API_KEY, "test-placeholder");
      assert.equal(options.env.RUNNER_CONTRACT_SENTINEL, "synthetic-parent-value");
      return { status: 0 };
    }), 0);
    assert.equal(calls, 1);
    assert.equal(process.env.NODE_ENV, "synthetic-parent-value");
  } finally {
    for (const name of names) {
      if (original[name] === undefined) delete process.env[name];
      else process.env[name] = original[name];
    }
  }
});

for (const [name, result, expected] of [
  ["test failure", { status: 7 }, 7],
  ["spawn failure", { error: new Error("synthetic failure"), status: null }, 1],
  ["signal termination", { signal: "SIGTERM", status: null }, 1],
  ["missing exit status", { status: null }, 1],
]) {
  test(`portable test entry reports ${name} as failure`, () => {
    assert.equal(runTests([], () => result), expected);
  });
}
