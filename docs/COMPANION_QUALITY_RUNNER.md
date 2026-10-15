# Four-request companion quality candidate — review only

No API call, Render Shell access, model activation, merge or deployment was performed to create this artifact. This is an independent branch from main; PR55/57/58 remain separate. Parent independent review is required before the operator executes any live command.

## Frozen provenance

App source: exact PR58 `b84c52428ce043a145c96e04ecb7b18dc63e6fc5`. `build_chat_quality_fixtures.cjs` reads only three pinned Git source blobs: server.js, voice_prompt_policy.js and companionChatService.js. It extracts the actual persona, pure prompt builder, language/boundary policy and chat route memory/context assembly into an isolated VM, then captures the actual service request using a fake client. It never requires server.js, starts the app or accesses runtime data. The source SHA-256 values and all complete request bodies/hashes are in `scripts/fixtures/companion_quality.json`.

Regenerate/check offline with `node scripts/build_chat_quality_fixtures.cjs`; `--write` deliberately rebuilds the fixture and embedded runner data and therefore requires a new artifact review/hash. CI fetches the exact source commit before checking regeneration; it does not depend on a different PR being merged. The deployed runner loads no app code or fixture file: the four bodies are embedded. Only n=1, stream=false, store=false and service_tier=default are added to captured app parameters as evaluation controls.

Fixed order: temporary-boundary with gpt-4o-mini, same case with gpt-6-luna, cancelled-move with gpt-4o-mini, same case with gpt-6-luna. The first case supplies a synthetic walking/family memory and declines discussing the daughter while requesting flowers. The second supplies uncertainty followed by cancellation of a move and a future thought about walking. Exact inputs are inspectable in the fixture. Both use actual app temperature 0.6 and 220 output cap; Luna uses none reasoning. No arbitrary prompt/model/file input, tools or additional cases are accepted.

Frozen runner commit: `d7c7dd3c1fedb7a7575c9e13502549ba8d30770d`.

- Runner SHA-256: `93c8043578a56d51a13e23f916797c20a013ba68efd675db69ad0106ac452230`
- Fixture file SHA-256: `7477a98cf49408bac31f143eb7f8da91a56c0f64961fd07bf3c7e4dfc60d783b`
- temporary-boundary / baseline body: `85189ebe4bf9334904a5c436a39db922da37ec204299e350b6c1de0c1edfc53f`
- temporary-boundary / Luna body: `e7928382f01bdb72da91a6eac110809ad1c2e5539ab27601f524b20f87c4a875`
- cancelled-move / baseline body: `c8575a16cb1fcb8ba25f3dd93b69f2ff8b8df16a14a7ec10a2f878d6e3ea35ed`
- cancelled-move / Luna body: `79c3bed7f34ae6060cf176c343d1b595055c55d30b8afe70e5a59bb55952ae7f`

Hashes are UTF-8/LF, file hashes include final newline, body hashes use JSON.stringify(body). The pinned runner is unchanged in subsequent documentation/launcher commits.

## Budget is cumulative

The user already ran the distinct PR57 basic smoke once: 88 input and 41 output tokens, both pass, exit 0. Its uncached standard base estimate is **$0.0000293**, actual billing unknown. Do not rerun that smoke. The overall authorization remains **$2**, not a new budget for this artifact.

Published prices checked on 2026-10-15: [Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) highest input category $0.125/M (cache writes), output $0.50/M, full context 1.05M; conservatively apply long-context 2x input/1.5x output, Fast 2x and regional 1.1x even though these small fixed requests select default tier. Two requests cost at most `2*(1.05*.125*2*2*1.1 + 220/1e6*.50*1.5*2*1.1) = $1.155726` under those published assumptions. [gpt-4o-mini](https://developers.openai.com/api/docs/models/gpt-4o-mini) standard rates are $0.15/M input, $0.60/M output, context 128K: `2*(128000/1e6*.15 + 220/1e6*.60) = $0.038664`.

Four-request conservative published-price bound: **$1.194390**. Including the prior base estimate: **$1.1944193 before tax**, not a measured bill or an account-level spending guarantee. Rates, account baseline availability (gpt-4o-mini is marked deprecated), taxes/custom prices and prior actual charges must be reconciled before execution; if the actual baseline differs, do not silently substitute it. The CLI attestation is not a billing query or provider-side hard cap. No budget is refunded on error/timeout: in-flight requests may still bill. There is no persistent cross-process lock; **never rerun manually after success, failure, disconnection or ambiguous outcome** without reconciling the shared budget and obtaining review for another attempt. No parallel paid evaluation.

## Execution/output boundaries

Default dry-run prints plan/hashes/costs, loads no SDK and reads no credential. Live mode additionally requires three explicit flags, approved prior-charge/budget review, and installed SDK 4.104.0. Only the SDK uses the inherited credential; no copying, display or storage. Node module loading necessarily reads installed code; no app/config/data files are loaded. The fixed API endpoint is https://api.openai.com/v1/chat/completions. Exact body/URL validation, zero retries, redirect:error and sequential at-most-four sends apply. Any technical failure, bad usage, refusal, truncated/filtered/tool output or invalid response stops subsequent sends.

Each result includes fixed model/case/request hash, sanitized numeric usage, bounded finish/refusal status, elapsed milliseconds and up to **4096 UTF-8 bytes** of synthetic reply. JSON serialization escapes terminal controls. Larger replies are suppressed (not silently truncated) and stop the batch; recognizable secret-shaped content is suppressed. No raw SDK errors, headers, request IDs, environment values or arbitrary metadata are printed. There is no real resident data or secret in the model's input; synthetic replies remain untrusted model output, never shell instructions. The runner cannot promise arbitrary hallucinated strings are semantically secret-free; it has no real secrets in the prompt to disclose.

`transportValid` is not a quality pass. Every received result says `quality: human-review-required`. First technical failure stops automatically; subjective quality requires manual assessment of returned text and does not auto-trigger retries. Compare warmth/short Traditional Chinese, boundary respect/no family probing, no invented move/address/facts, correct cancellation/future language and elapsed time. Two cases are not comprehensive quality, tail-latency, app/alert, Vision, STT, Realtime or device validation.

Limits: 20s request timeout including body read; 90s runner wall deadline; external 95s timeout plus 2s kill grace; 10s CPU; 64 MiB V8 old heap; 128 MiB sampled RSS stop; 8 KiB HTTP headers; 64 KiB response; 4 KiB reply. Sampled RSS is not a cgroup quota and native allocation may exceed it briefly. Existing Render Shell shares production memory: inspect headroom separately before any approved execution. No new service, key, route, dependency installation or persistent permission is required.

## Single-paste command draft

Use only after review, in the existing backend working directory where SDK 4.104.0 is installed. The command below is complete and **dry-run by default**. It downloads only the fixed public runner commit to a subshell variable, with curl config disabled and bounded HTTPS/time/size; redirects are not followed. curl 8.4.0 or newer is required so unknown-length responses also obey the size bound; older or unrecognized versions stop without installation. LC_ALL=C makes the shell length check count bytes. It checks the fixed hash before Node receives any source. Curl/download/hash failure stops without loading SDK. This is not curl-pipe-to-execute.

For a later explicitly approved live invocation, change only the final `quality_once --dry-run` to `quality_once --execute`. Do not paste both invocations. Source variables die with the subshell, and the launcher prints/returns the original exit code even with errexit. Diagnostic/preload/TLS-disable environment values are removed for the child only; the service configuration is unchanged. Do not run this command during this implementation/review task.

```bash
# Review-only Bash launcher. Default is dry-run; live execution requires separate approval.
quality_once() {
  local quality_rc
  if (
    set -o pipefail
    export LC_ALL=C
    case "${1:---dry-run}" in
      --dry-run) quality_args=(--dry-run) ;;
      --execute) quality_args=(--execute --standard-pricing-reviewed-2026-10-15 --prior-charge-and-overall-budget-reviewed) ;;
      *) exit 2 ;;
    esac
    command -v curl >/dev/null && command -v sha256sum >/dev/null && command -v timeout >/dev/null || exit 2
    quality_curl_version=$(curl --disable --version) || exit 2
    [[ "$quality_curl_version" =~ ^curl\ ([0-9]+)\.([0-9]+)\.([0-9]+)\  ]] || exit 2
    (( 10#${BASH_REMATCH[1]} > 8 || (10#${BASH_REMATCH[1]} == 8 && 10#${BASH_REMATCH[2]} >= 4) )) || exit 2
    ulimit -c 0 || exit 2
    ulimit -t 10 || exit 2
    quality_source=$(curl --disable --fail --silent --show-error --proto '=https' --tlsv1.2 --max-redirs 0 --connect-timeout 5 --max-time 10 --max-filesize 131072 'https://raw.githubusercontent.com/Ou931023/pet_companion_app/d7c7dd3c1fedb7a7575c9e13502549ba8d30770d/scripts/companion_quality.cjs' && printf '\001') || exit 2
    quality_source=${quality_source%$'\001'}
    test "${#quality_source}" -le 131072 || exit 2
    quality_sha=$(printf '%s' "$quality_source" | sha256sum) || exit 2
    test "${quality_sha%% *}" = '93c8043578a56d51a13e23f916797c20a013ba68efd675db69ad0106ac452230' || exit 2
    printf '%s' "$quality_source" | timeout --signal=TERM --kill-after=2s 95s \
      env -u NODE_OPTIONS -u NODE_PATH -u DEBUG -u NODE_USE_ENV_PROXY -u NODE_DEBUG -u NODE_DEBUG_NATIVE -u NODE_V8_COVERAGE -u NODE_REDIRECT_WARNINGS -u NODE_TLS_REJECT_UNAUTHORIZED \
      node --max-old-space-size=64 --max-http-header-size=8192 - "${quality_args[@]}"
  ); then
    quality_rc=0
  else
    quality_rc=$?
  fi
  # Source and hash variables existed only in the ended subshell; cleanup cannot erase status.
  printf '{"launcherExitCode":%s}\n' "$quality_rc"
  return "$quality_rc"
}
quality_once --dry-run
```
