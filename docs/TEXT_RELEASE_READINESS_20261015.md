# Text release readiness — 2026-10-15

## Reported execution evidence, not a replay

The user reports executing the reviewed PR57 probe once in the existing Render Shell:

| Case | Model | Pass | Input tokens | Output tokens | Total |
| --- | --- | --- | ---: | ---: | ---: |
| synthetic-chat | gpt-6-luna | true | 39 | 28 | 67 |
| synthetic-memory | gpt-6-luna | true | 49 | 13 | 62 |

Reported launcherExitCode: 0. Total: **88 input + 41 output = 129 tokens**. This is user-supplied execution evidence; the agent did not observe the shell or independently read the billing ledger. Do not rerun this batch or schedule parallel paid tests.

At the [published standard rates](https://developers.openai.com/api/docs/models/gpt-6-luna), checked 2026-10-15, the uncached-input base estimate is `88 / 1,000,000 * $0.10 + 41 / 1,000,000 * $0.50 = $0.0000293` before tax. This is **not $0 spend**, and is not a measured charge. Cache categories, processing premiums and actual billing adjustments were not reported. Actual billed amount remains unknown. The one overall validation budget remains $2; nominal remaining budget on this base estimate is $1.9999707, not a reconciled spendable balance or permission to start another batch.

These two results establish basic Luna request/response availability and two narrow fixture verdicts only. They do not establish app prompt quality, the full memory content matrix, storage/embedding behavior, source grounding, Vision, STT, Realtime, latency under load or device behavior.

## Repository checkpoint

At this preparation checkpoint: main is `dc07c3d1913c196b3a2bbb51cf9e415b94c36d1a`; PR55 runtime candidate is `bd7f604d6720378e61c6f19af9e52a8185ee7ebf`, still draft/unmerged; PR57 is `2c4dcd5703c18977c2cf24696ce6326df5f70a6a`, still draft/unmerged. Both local worktrees were clean before this documentation/test update. PR55 started before the offline-tools-only PR56 merge; any split candidate must use current main and obtain its own exact-commit checks. No production settings were inspected or changed here.

## Copy/paste read-only settings inspection

The following command loads no SDK/app/files and makes no network request. It reads only eleven named model/language settings. Known model identifiers are an exact conservative allowlist, not a permissive pattern that could echo a secret disguised as a model ID. Unknown/custom/snapshot values are reported as REDACTED, even if potentially legitimate. Empty means EMPTY, absent means UNSET. Do not paste hidden values to resolve a REDACTED result; assess any needed override separately with the operator. This describes configured overrides, not effective defaults or model entitlement.

Only child-process diagnostic/preload environment is removed; service configuration is unchanged.

```bash
env -u NODE_OPTIONS -u NODE_PATH -u DEBUG -u NODE_DEBUG -u NODE_DEBUG_NATIVE -u NODE_V8_COVERAGE -u NODE_REDIRECT_WARNINGS -u NODE_TLS_REJECT_UNAUTHORIZED node - <<'MODEL_SETTINGS'
const keys = ['COMPANION_CHAT_MODEL','MEMORY_MODEL','MEMORY_EXTRACT_MODEL','CONVERSATION_TITLE_MODEL','SEARCH_SUMMARY_MODEL','WEB_SEARCH_SUMMARY_MODEL','DAILY_CARE_VISION_MODEL','STT_MODEL','REALTIME_MODEL','LEGACY_REALTIME_MODEL','STT_LANGUAGES'];
const models = new Set(['gpt-4o-mini','gpt-4o','gpt-6-luna','gpt-transcribe','gpt-4o-transcribe','gpt-4o-mini-transcribe','gpt-realtime','gpt-realtime-2.1']);
for (const key of keys) {
  const raw = process.env[key];
  let value = raw === undefined ? 'UNSET' : raw === '' ? 'EMPTY' : 'REDACTED';
  if (typeof raw === 'string' && raw.length <= 80) {
    if (key !== 'STT_LANGUAGES' && models.has(raw)) value = raw;
    if (key === 'STT_LANGUAGES' && /^(zh|zh-tw|cmn|en)(\s*,\s*(zh|zh-tw|cmn|en))*$/.test(raw)) value = raw.split(',').map(x => x.trim()).join(',');
  }
  console.log(key + '=' + value);
}
MODEL_SETTINGS
```

Returning UNSET is expected for new PR55 variables not deployed yet. Main's existing defaults remain authoritative. Do not change any variable as part of this read-only step.

## Smallest release route

**Split is feasible; do not merge PR55 whole or merely mask its untested changes with environment overrides.** PR55 uses one shared DEFAULT_TEXT_MODEL for both text and Vision, changes file STT, and changes GA/beta model selection semantics. Environment-only masking would leave untested code/guard behavior and a changed beta override contract deployed.

The smallest candidate should switch **companion text chat only** from current main in a separate reviewed branch. Keep its default old until validation completes, then make a separately reviewed default/override activation. Port only its Luna parameter handling and completion rejection plus the tightly scoped server handling that preserves existing authorized risk side-recording for rejected nonempty completions. Use a chat-specific default; do not export a shared default used by Vision. Do not cherry-pick PR55's whole server.js or mixed helper file. Preserve all other server hunks byte-for-byte where possible.

Leave active/legacy memory extraction, greeting, titles and search on their existing models for this first candidate. The tiny memory smoke does not validate the real extractor prompt or justify moving these consumers together. A subsequent text-only batch can migrate them after their own fixture and contract evaluation. Leave Vision, file STT, GA/beta Realtime, in-session transcription, embeddings, Taigi ASR and device/signing changes outside both text releases. No schema or historical-data migration is needed.

Required gates still missing for a chat-only release:

1. Read the allowlisted configured overrides: COMPANION_CHAT_MODEL wins over MEMORY_MODEL. Avoid changing MEMORY_MODEL globally because it also controls other consumers. Confirm the actual target/revision and current overrides before designing rollback.
2. Build the actual chat-only diff against current main; run real installed-SDK serialization for exact app parameters (temperature 0.6, none, 220-token cap), legacy override behavior and full backend/CI. The two smoke calls did not use the application's complete prompts or this output cap.
3. Re-run content/behavior regressions using the actual companion prompt/context and returned data: Traditional Chinese tone, short answers, temporary refusal and reopening, uncertain/future/cancelled facts, no invented memory/source facts, malformed/empty/refused/filtered/truncated replies, provider errors and no leaked internal marker. Preserve consent, risk-side-recording, cooldown and recipient behavior using fakes only; no production alerts.
4. Plan, review and budget any additional model quality/latency comparison against the current chat model using synthetic app-shaped inputs; **do not execute it now**. A generic two-case smoke is insufficient. Reconcile billing/remaining overall budget first; sequential only, no repeat of the completed batch.
5. Independent exact-diff review, exact-commit CI, data compatibility, concrete rollback (revert candidate or restore chat-only override), target commit verification and approved synthetic post-deploy checks without production care alerts. No release until these pass.

For later extraction/title/search migrations additionally require the existing 68-case content matrix through actual extraction prompt, persistence stub, embedding input, memoryText/memorySummary/context/greeting, both mixed-clause orders, uncertainty/cancellation/future controls; valid JSON/source grounding and one-row-per-turn compatibility. These are not prerequisites to keep those paths unchanged during a chat-only release.

This update is preparation only. No split runtime candidate has been implemented, merged or deployed; no new model request, Shell session, account billing query or production configuration change was performed by the agent.
