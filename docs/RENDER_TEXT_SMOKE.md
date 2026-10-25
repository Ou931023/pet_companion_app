# One-time synthetic text probe — review only

Prepared 2026-10-15; refreshed against main on 2026-10-23. The later readiness record reports one user-executed batch (88 input + 41 output tokens; both narrow fixture verdicts passed), not an independently observed run or reconciled bill. Actual billed amount remains unknown; the previous zero-spend claim is obsolete. This refresh performs offline validation only; prior account spend is not verified here. Do not rerun that completed batch. For any different future probe, this document or a PR merge is not authorization: live execution needs a separately confirmed scope, current pricing/access checks and authorization. No paid request or Render Shell execution occurs in this refresh.

## Artifact and isolation

`scripts/render_text_smoke.cjs` is standalone CommonJS and defaults to dry-run. Its SHA-256 (UTF-8, LF, including final newline) is:

`84a84e1ae57c96763d4732ee9bb28503b70bc2d8f2a152cafd08c640801af293`

It loads no application code, dotenv, DB, scheduler, notification, or test runner. It accepts no input files or custom prompts and makes no application API call. Node necessarily loads its own runtime and installed SDK code; "no file reads" means no application/configuration/data files, not a claim that module loading avoids the filesystem. The SDK alone consumes the inherited OpenAI credential during an explicitly enabled live run. Nothing copies or prints that credential. Dry-run does not even load the SDK.

Only the installed OpenAI SDK **4.104.0** is accepted, matching the repository lockfile and local serialization tests. No package installation is needed. Its `chat.completions.create` forwards the fixed JSON fields; offline tests exercise the real SDK with a fake key and fake fetch. This establishes wire serialization, not actual account/model access.

The two cases are a short synthetic Chinese chat and a synthetic durable fact mixed with a temporary boundary. They use `gpt-6-luna`, `reasoning_effort: none`, `max_completion_tokens: 256`, `n: 1`, `stream: false`, `store: false`, and `service_tier: default`. No tools. Exact request bodies and the official `https://api.openai.com/v1/chat/completions` URL are checked before transport. Redirects and retries are disabled. A failed first case stops the batch. Outputs contain fixed case/model labels, boolean verdicts and numeric token usage only; no provider text, error messages, headers or environment values.

## Cost derivation and limits

[OpenAI GPT-6 Luna model documentation](https://developers.openai.com/api/docs/models/gpt-6-luna), checked 2026-10-15, lists a 1,050,000-token context, per-million token prices of $0.10 input, $0.01 cached input, $0.125 cache write, and $0.50 output. Above 272K input tokens the full request uses 2x input/cache and 1.5x output pricing. Fast processing is 2x; regional processing adds 10%.

Instead of guessing token counts from Chinese character counts, use the **entire documented context window** as the input ceiling, the highest input category price, and all listed premiums, including Fast even though the request selects default tier:

```text
input per request  <= 1,050,000 / 1,000,000 × $0.125 × 2 × 2 × 1.1 = $0.5775
output per request <=       256 / 1,000,000 × $0.50  × 1.5 × 2 × 1.1 = $0.0004224
two-request bound <= 2 × ($0.5775 + $0.0004224) = $1.1558448
```

This intentionally overcounts context by also allowing 256 output tokens separately. Actual fixed inputs are tiny; this is a conservative published-price bound, not a measured bill or arbitrary reserve. It assumes the documented context/output enforcement and applicable published token rates. It excludes taxes, custom contract rates, price changes and unrelated production traffic. The execution flag attests that those pricing assumptions have been reviewed; if they cannot be established, **do not execute**. There is no provider-side account spending lock. Process termination does not cancel already incurred or in-flight provider charges.

The two-call limit applies to **one invocation**. There is intentionally no persistent lock/file or new service. A second invocation would create another batch: do not rerun after timeout, error, interruption or ambiguous outcome. Reconcile billing before considering any subsequent execution under the remaining original budget. Do not repurpose the unused budget for STT, image or Realtime tests without a reviewed plan.

## Render execution preparation (do not run before approval)

Existing Dashboard Shell availability is confirmed by the user. [Render documentation](https://render.com/docs/ssh) says this shell shares the live instance's memory pool. This procedure creates no service, SSH key, route or deploy. Ephemeral instances are separate billed compute and are not part of this plan.

Use the already authenticated Dashboard Shell, after authorization. Confirm its current directory is the existing `backend/stt_proxy` deployment directory. Do not use `npm start`, `npm test`, `require(server.js)`, `printenv`, `env` without a command, or inspect `.env`. Check that the service has enough memory headroom for an additional Node process. If headroom is unknown or the instance is under pressure, stop. Heap and sampled RSS limits do not provide OS-level isolation or guarantee zero production impact.

Copy the **reviewed exact script from the final commit**, not a moving branch. Paste it into this shell variable; the placeholder must be replaced by the complete source including its final newline. This does not read application files or put credentials in shell history. `read` returns nonzero at EOF by design.

```bash
IFS= read -r -d '' probe_source <<'SMOKE_SOURCE' || true
PASTE THE COMPLETE REVIEWED scripts/render_text_smoke.cjs HERE
SMOKE_SOURCE
expected_probe_sha=84a84e1ae57c96763d4732ee9bb28503b70bc2d8f2a152cafd08c640801af293
actual_probe_sha=$(printf '%s' "$probe_source" | sha256sum)
test "${actual_probe_sha%% *}" = "$expected_probe_sha" || { echo 'STOP: source hash mismatch'; unset probe_source; }
```

Stop on mismatch; do not fix it by changing the expected hash. First run dry-run using stdin, with ambient Node preload/debug/proxy options removed for this child process only:

```bash
printf '%s' "$probe_source" | env -u NODE_OPTIONS -u NODE_PATH -u DEBUG -u NODE_USE_ENV_PROXY -u NODE_DEBUG -u NODE_DEBUG_NATIVE -u NODE_V8_COVERAGE -u NODE_REDIRECT_WARNINGS -u NODE_TLS_REJECT_UNAUTHORIZED \
  node --max-old-space-size=64 --max-http-header-size=8192 - --dry-run
```

After parent review and explicit execution approval, run **once**, only if the hash matches and `timeout` is already available. No installation or fallback if unavailable:

<!-- live-launcher -->
```bash
run_smoke_once() {
  local probe_status
  if (
  command -v timeout >/dev/null || exit 2
  actual_probe_sha=$(printf '%s' "$probe_source" | sha256sum)
  test "${actual_probe_sha%% *}" = "$expected_probe_sha" || exit 2
  ulimit -c 0 || exit 2
  ulimit -t 10 || exit 2
  printf '%s' "$probe_source" | timeout --signal=TERM --kill-after=2s 65s \
    env -u NODE_OPTIONS -u NODE_PATH -u DEBUG -u NODE_USE_ENV_PROXY -u NODE_DEBUG -u NODE_DEBUG_NATIVE -u NODE_V8_COVERAGE -u NODE_REDIRECT_WARNINGS -u NODE_TLS_REJECT_UNAUTHORIZED \
    node --max-old-space-size=64 --max-http-header-size=8192 - \
    --execute --standard-pricing-reviewed-2026-10-15
  ); then
    probe_status=0
  else
    probe_status=$?
  fi
  unset probe_source
  printf '{"launcherExitCode":%s}\n' "$probe_status"
  return "$probe_status"
}
run_smoke_once
```
<!-- /live-launcher -->

The function captures the subshell status before cleanup, prints it and returns that same status (including timeout 124). It preserves failure even when the calling shell enables `errexit`. The launcher removes `NODE_TLS_REJECT_UNAUTHORIZED` only for this child; direct live invocation refuses value `0` before SDK loading or credential use. Neither changes the service environment. Linux CI tests this exact documentation block with fake executables, including success, failure and an actual shortened GNU timeout; no model request occurs.

Limits: 64 MiB V8 old-generation heap, 8 KiB HTTP headers, 64 KiB response body, 20-second per-request abort covering body consumption, 60-second internal wall timer, 128 MiB sampled RSS stop, 10-second CPU limit and 65-second external wall timeout with 2-second kill grace. RSS can briefly exceed the sampled threshold and native allocations are outside the V8 heap limit. These are containment measures, not a hard cgroup memory quota. No provider completion text is printed even on failure. Retain only the sanitized JSON lines and exit status. Timeout/termination means cost unknown, never free retry.

## Verification and release boundary

Run offline with `node --test scripts/render_text_smoke.test.cjs` after normal project dependencies are available. For this Windows worktree only, `SMOKE_TEST_SDK_DIR` can point to the existing sibling backend directory; tests pass an explicitly fake key and do not use its environment secrets. CI installs the existing lockfile dependencies and uses fake transport. No dependency change.

Tests cover dry-run/no SDK load, stdin execution, fixed wire parameters through SDK 4.104.0, two-request limit, first-error stop, HTTP errors, redirect refusal policy, network throw, oversized/stalled response bodies, malformed/refused/truncated/tool output, memory pollution and sensitive sentinel suppression.

A successful smoke result only confirms two direct model calls and these narrow output checks. It does not run the application's memory extractor, embedding, alert handling, STT, Realtime, or full PR55 release regression. PR55 remains separate and unmerged pending its own review and deployment gates. Rollback for this artifact is to stop using the script; no runtime state or schema is changed. No model-setting inspection is bundled to avoid unnecessary environment access.
