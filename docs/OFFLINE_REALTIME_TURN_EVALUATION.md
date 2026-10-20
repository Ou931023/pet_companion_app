# Offline synthetic turn evaluation

This standalone tool checks measurement and ordering logic only. It does not connect to an app, collect runtime events, contain audio/transcripts, call models, or send alerts. It cannot establish real latency, VAD quality, perceived audio onset, or correctness of the runtime microphone policy.

The current controller disallows interruption during thinking/speaking. See `test/voice_agent_controller_realtime_lifecycle_test.dart` (thinking/speaking cannot restart; response.done does not finish playback) and `lib/services/realtime_voice_service.dart` (output buffer start/stop versus generation done). This tool does not change those files or policies.

Run with Node 22 or 24, no dependencies or credentials:

```sh
node scripts/evaluate_realtime_turns.mjs scripts/fixtures/realtime_turns.synthetic.json
node --test scripts/evaluate_realtime_turns.test.mjs scripts/read_voice_language_diagnostics.test.mjs
```

The CLI reads one local JSON fixture (at most 64 KiB), writes a JSON report to stdout and creates no files. Exit 0 means a valid report was produced, not that all turns are complete. Exit 2 means invalid input/usage. Errors never echo file contents, paths or exceptions. Use only deliberately authored synthetic fixtures; do not pass runtime logs. `synthetic: true` is a declaration, not automatic detection of real data.

## Input contract (fixture schema only)

Root has exactly `schemaVersion: 1`, `synthetic: true`, and `events` (maximum 1000). Each event has exactly these fields:

| Field | Meaning |
| --- | --- |
| sequence | Global strictly increasing arrival index; never sorted by the evaluator |
| atMs | Synthetic monotonic elapsed milliseconds within a session/generation; equal times allowed |
| session, generation, turn | Synthetic numeric identifiers; pairing requires all three to match |
| event | One of the event codes below |

All numeric fields are nonnegative safe integers. Unknown keys, enums, oversized inputs, reversed sequence/time and non-finite values are rejected. No strings carrying identifiers, transcripts, audio or arbitrary labels are accepted. The fixture schema is not a production API or persisted app data structure.

Event codes: `input.started`, `input.ended`, `output_audio_buffer.started`, `output_audio_buffer.stopped`, `response.done`, `synthetic.continuation`, `synthetic.backchannel`. The input names are normalized fixture annotations, not a new runtime collector or automatic mapping from service events.

`synthetic.continuation` explicitly declares that an earlier input-ended candidate was a pause inside the same utterance. Its timestamp marks resumption; it replaces that candidate and requires a later `input.ended`. Do not add another `input.started` for that resumption. Silence duration alone never establishes continuation. `continuationGapsMs` reports the authored pause interval, not a VAD error rate. Continuation after output starts makes the turn invalid; it cannot retroactively manufacture a valid or negative latency.

`synthetic.backchannel` marks an authored short response during playback. It is reported as unsupported under the current no-interruption policy, excluded from latency measurements, and does not imply the microphone captured it. A label outside playback is invalid.

## Pairing and results

A complete turn requires input start, final input end, output buffer start, and output buffer stop in arrival/time order. The reported input-end-to-output-start interval is measured between those last two boundaries; playback duration uses buffer start/stop. `response.done` only records generation completion and never substitutes for a missing playback stop. Missing required events produce `incomplete` with explicit names and null metrics.

The first event of each kind wins. Same-kind/same-time repeats within a turn are reported as `duplicate_event`; different-time repeats are `conflicting_duplicate` and invalidate measurements. Continuation explicitly opens a new input-end candidate, unlike a duplicate. Invalid ordering is never repaired by sorting. A continuation cannot erase an earlier end-before-start contradiction. Status precedence is invalid, incomplete, unsupported_policy, then complete; all issues remain visible.

Session/generation scopes are contiguous. A boundary closes the previous scope; late events for a closed scope are ignored with `closed_scope_event` diagnostics and cannot finish an old turn. New scopes may reset their clock. Turns cannot be paired across session, generation or turn identifiers. No inferred reconnects, response IDs or semantic matching are used.

The committed fixture demonstrates a normal turn (300 synthetic ms), a labelled long pause (300 synthetic ms after its final end), unsupported backchannel, generation-done with missing playback stop, duplicate start, and a generation boundary with a late old event. Tests additionally cover session/turn boundaries, contradictory order, unlabelled pauses, malformed/private fields, size bounds and empty input. These numbers are fixtures, not observed service performance. There are no percentile or quality claims.

Rollback: remove the standalone script, test, fixture, documentation and its CI test step. No runtime migration, stored-data change or deployment action is needed. PR #55's model migration is unrelated and remains on its separate branch.

## Paired Mandarin / Taiwanese scenario preparation (2026-10-20)

`scripts/fixtures/realtime_turns.paired.synthetic.json` contains **20 authored scenarios in 10 matched pairs** (`zh-TW`, `nan-TW`). It is a reviewable experiment specification, not a speech corpus. The Taiwanese wording is a draft awaiting fluent-speaker review; labels are intended language, not detected language. No speaker, recording, model inference or human audio annotation is represented.

Each scenario has a unique ID, pair/category, draft prompt, strict event-only `fixture`, and a separately authored full `expected` evaluator report. Root metadata explicitly records audio not collected, annotation not performed, language review pending and expectations manually defined from the event contract. Do not regenerate expected reports from evaluator output to make a failing test pass.

| Pair | Intended scenario | Authored event expectation |
| --- | --- | --- |
| 01 | Simple story request | Complete; generation done and playback stop remain separate |
| 02 | Short in-utterance pause | Explicit continuation after 300 synthetic ms; use the final end |
| 03 | Long in-utterance pause | Explicit continuation after 2000 synthetic ms; silence is not automatically a final boundary |
| 04 | Unlabelled silence control | No continuation annotation; do not infer one from 2800 synthetic ms |
| 05 | Self-correction before completion | Explicit continuation; evaluates boundaries only, not understanding the correction |
| 06 | Short acknowledgement during playback | `unsupported_policy`; null timing metrics under current no-interruption policy |
| 07 | Generation ends without playback-stop evidence | `incomplete`; response.done cannot stand in for audio stop |
| 08 | Duplicate output-start event | First timestamp retained; duplicate diagnostic remains visible |
| 09 | New generation followed by old output events | Two incomplete turns; closed-generation events excluded |
| 10 | Output begins before labelled continuation | `invalid`; never report an apparently valid latency |

Within each pair the synthetic events and expected reports are deliberately identical. The two language rows are matched controls, **not 20 independent observations**, and cannot demonstrate language parity. Prompt text does not cause the event timings; ellipses and bracketed stage directions are authoring cues, not measured pauses or spoken words. The evaluator receives only `scenario.fixture`, never the prompt. Existing schema rejection of transcripts/audio/unknown event fields remains intact.

Run all contract and regression checks with the existing command (also already run by App quality CI):

```sh
node --test scripts/evaluate_realtime_turns.test.mjs scripts/read_voice_language_diagnostics.test.mjs
```

To inspect one case with the existing evaluator API, without a new runner:

```sh
node --input-type=module -e "import {readFileSync} from 'node:fs'; import {evaluateTurns} from './scripts/evaluate_realtime_turns.mjs'; const pack=JSON.parse(readFileSync('scripts/fixtures/realtime_turns.paired.synthetic.json','utf8')); console.log(JSON.stringify(evaluateTurns(pack.scenarios.find(s=>s.id==='03-nan-TW').fixture),null,2));"
```

The pack itself is not a CLI fixture: the original CLI accepts only the strict event schema. Tests validate pair coverage/IDs, metadata, intended languages, paired timelines and each complete report, including nulls, missing boundaries, issues and closed-scope diagnostics. Negative format checks reject a missing pair, duplicate language, invented audio evidence and transcript insertion into the event schema. No runtime policy, model, CI configuration or collector changes are needed.

### Gates before any real experiment or quality claim

1. Have fluent Mandarin/Taiwanese reviewers confirm natural wording and paired intent, including acceptable spelling variants. Record reviewer decisions separately; the current language status remains pending.
2. Establish an explicitly authorized, consented recording protocol and retention/access rules before collecting any audio. This batch neither collects nor imports audio, including the unrelated existing audio fixture. Prefer a separate synthetic-speaker pilot before any elder study; synthetic speech is still not elder-use evidence.
3. Define annotation rules before evaluation: input start/final end versus continuation, actual playback start/stop, generation/session identity, acknowledgement versus interruption intent. Obtain independent human audio annotations and adjudicate disagreements. Do not map punctuation automatically to VAD boundaries.
4. Keep event arrival order and align clocks in a separately reviewed instrumentation plan. Distinguish service-buffer events from acoustically perceived output. Annotate missing endpoints instead of guessing or silently dropping failures.
5. Choose a verified model and approved cost/data plan separately. Current work makes no calls and does not authorize downloading models, spending money or changing microphone/interruption behavior.
6. Predefine sample design, speaker/device/noise strata, scoring denominators and exclusion reporting before computing ASR accuracy or latency percentiles. The 10 paired templates are insufficient for representative p95, language parity or elder outcomes. Report incomplete/invalid/unsupported cases explicitly; never turn the authored milliseconds into measured performance.

No speculative prefetch is introduced. `/api/memories/context` uses buildMemoryContext with recordUsage defaulting to true and can update usage counts; it must not be treated as a read-only probe. This batch does not call that route or change memory semantics. Existing controller lifecycle tests remain the source of runtime-policy coverage; scenario-only tests do not prove microphone behavior.

Rollback for this batch: remove the paired pack and appended tests/documentation. The original evaluator and fixture remain usable. No API/data migration or deployment is involved. Deliver as a draft PR for review; do not merge or publish a mobile build as part of this batch.
