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
