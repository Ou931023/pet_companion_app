# Voice Release Acceptance - 2026-09-22

## Stability Investigation - 2026-09-27

User priority: conversation reliability before engagement features or store
submission. Taiwan 50+ audience research, family meeting reminders and spoken
onboarding are recorded as subsequent work, not completed features.

Confirmed source-level gaps (not proof of the failed speech case's sole cause):

- Client context updates replace full session instructions with a shorter
  persona; initial backend pet name and memory are not preserved in that update.
- The active `taigiRealtime` route uses the OpenAI Realtime transcript directly;
  it does not submit live microphone audio to ASR-26. Backend call transcription
  is configured with `language: "zh"`. No ASR/model change has been made here.
- Configuration ACK and actual audible language are distinct acceptance checks.

A bounded `flutter attach --profile --machine` probe reported daemon/app start,
but no VM discovery within 65 seconds. Machine logs and endpoint credentials were
discarded, not displayed or persisted. The phone was subsequently confirmed
unlocked and Runner still running; lack of discovery is not proof of an App crash.
Remaining disk space was about 4.2 GiB; no clean rebuild was performed.

The final sanitized reader has **33/33 synthetic Node tests passing**, including
malformed/oversized payloads, timeout/cancellation, ambiguous/missing extension,
private sentinel suppression, strict schema v2 and bounded install/launch mode.
This does **not** establish device capture. D1-C, P1-C and Reader v2-C received
architecture code-checkpoint approval; physical checks remain distinct.

Main independently ran the following group: **140/140 passed, exit 0**. The voice
owner separately reports 140/140 default, 140/140 diagnostic opt-in and seven-file
analysis with no issues. These are overlapping runs, not 420 unique tests.

```sh
flutter test --no-pub --concurrency=1 test/services/voice_language_diagnostics_test.dart test/realtime_language_sync_test.dart test/realtime_voice_service_test.dart test/voice_agent_controller_realtime_lifecycle_test.dart --reporter expanded
node --test scripts/read_voice_language_diagnostics.test.mjs
```

### Candidate 3 - 2026-09-27

- One incremental **1.0.0 (3), Profile** build completed in **40.5 seconds**,
  reported **107.2 MB**. Existing signing team/bundle identity and production API
  remain unchanged. `VOICE_LANGUAGE_DIAGNOSTICS=true` is opt-in for this nonrelease
  build; `SHOW_APPLE_SIGN_IN=false` remains this test configuration only.
- The bounded Flutter existing-binary install/launch attempt exited early. A
  device version check still showed build 2, so it was not counted as successful.
- The same artifact was then installed with native `devicectl`, without uninstall,
  data reset or another build. Device app info confirmed **version 1.0.0/build 3**
  at **23:09 Asia/Taipei**; native launch succeeded. No chat/account data was read.
- A single subsequent 15-second sanitized reader attempt timed out without VM
  discovery. Runner was independently confirmed still running afterward. No
  snapshot, `capture_ready`, live controller event or `baselineReady` evidence
  was obtained. Do not mislabel this as an App crash or a successful diagnostic.
- Disk space after build was approximately **6.3 GiB**. No Flutter clean, simulator
  creation or repeated rebuild was used.
- No post-update human speech acceptance has been performed. No microphone was
  automatically activated, no real notification sent, no backend deployment,
  commit or push performed in this round.

**Remaining gate:** restore the development diagnostic connection before asking
the user to repeat speech cases; then validate initial baseline availability and
the three failed scenarios on this same candidate. Do not broaden raw log capture
or silently replace the transport/model to bypass missing evidence.

Overall result remains **NO-GO**, no claim of ChatGPT/Siri-equivalent reliability.

## Device Follow-Up - 2026-09-27

**FAIL / NO-GO remains.** `devicectl device info apps --bundle-id
tw.edu.ncyu.im.aicompanion --columns '*'` confirmed the connected iPhone 14 Plus
has version **1.0.0, bundle version 2**, at the same installation path recorded
for the candidate. No rebuild, reinstall or application-code change was made
during this follow-up.

The user supplied the following audible-behavior observations. These were not
independently heard by the agent and no exact recognized transcript was obtained:

| Starting mode | Spoken request | User-observed result |
| --- | --- | --- |
| Taiwanese | Request Mandarin using Taiwanese | Does not switch |
| Taiwanese | Request Mandarin using Mandarin | Switches successfully |
| Mandarin | Request Taiwanese | Has not succeeded |

These are observations of behavior, not proof of ASR accuracy, parser matching
or service acknowledgement. Do not infer that either failing path is solely a
regex problem or solely a model/pronunciation problem.

Diagnostics were attempted without storing raw console output or transcripts:
a 180-second devicectl console window, then a terminal-backed window using
Flutter's `OS_ACTIVITY_DT_MODE=enable` launch option for 120 seconds. One
intermediate non-terminal launch attempt exited before capture. Both bounded
windows ended with zero allowlisted `VOICE_LANGUAGE` / `VOICE_LANGUAGE_ACK`
events. The exact overlap with the user's spoken attempts is not established.
Consequently diagnostic-to-audio correlation is **NOT COMPLETED**; zero events
must not be interpreted as either a successful switch or proof the parser did
not run. Device launch succeeding is not proof of a functioning log channel.

Next diagnostic gate: establish that the capture channel receives a known
language-state event before asking for another speech scenario. Then correlate
one failed Mandarin-to-Taiwanese attempt with final-command, preference, send,
ACK and next-response state. Keep the same candidate until evidence is captured;
do not replace the model/prompt merely on the basis of missing logs.

## Decision

**NO-GO for public release.** The user reports that spoken language switching
still fails on the installed iPhone build. Passing offline tests does not close
that report. Do not call a session configuration acknowledgement proof of spoken
language or pronunciation quality.

Baseline HEAD: `8fe8c0911b0cbe3c651e13c4132fba626f443508`.
The working tree includes uncommitted language parser changes and unrelated
pre-existing store assets/documents. The previously installed build was Profile,
using production API configuration and a personal development team, not a
TestFlight or App Store distribution build. Its launch succeeded; real language
switching did not pass user acceptance.

## Evidence Collected This Round

| Check | Result | Limit |
| --- | --- | --- |
| Subtitle, conversation UI, timeout, coordinator, login tests | 57 passed | Offline unit/widget tests, not microphone or OAuth-provider verification |
| Auth controller, native tools, tool confirmation, diary, reminder schedule tests | 70 passed | Injected test doubles; no real deletion, purchases, calls or notifications |
| Production-flag store readiness tests | 19 passed | Configuration/source assertions, not store approval or signing verification |
| Caregiver auth, provisioning UI, workspace loading, tasks, diary tests | 63 passed | Mix of static assertions and isolated JS execution; not live authorized workflows |
| Updated subtitle, home layout and bubble regression | 41 passed | Includes the earlier subtitle/bubble suite; do not add all rows as unique tests |
| Backend companion voice policy tests | 3 passed | Prompt/strategy assertions only, not live model output |
| Final language/controller/service/routing regression | 173 passed, independently rerun by main agent | Includes new background stop/health/connect late-success and late-failure cases; still uses controlled event injection |
| Static analysis of nine changed Flutter code/test files | No issues found | Does not validate real device speech |
| Production `/health` | HTTP response reports `status=ok`, `gpt-realtime` | Does not exercise a Realtime call, DB write or audio |
| Unauthenticated `/api/admin/elders` | HTTP 401 | Response body discarded; only this unauthenticated request checked |
| Hosted privacy and support pages | HTTP 200 | Availability only, not content/legal compliance certification |

No secrets, `.env` files or real resident records were read. No real caregiver
notifications, facility control or account deletion were triggered.

## Blocking and Unverified Items

Subtitle regressions reproduced and fixed this round: new streaming replies
retained an old manually selected page when sharing a text prefix; three-line
ellipsis hid text at large font sizes; pagination removed internal whitespace
and line breaks. These repairs preserve manual page controls. They do not add
audio timestamp alignment.

Voice regressions reproduced and fixed this round: residual speech events could
reopen the microphone before a pending language update was acknowledged; warm
idle, connecting and recovering states did not all stop on background entry;
stale recovery stop/health results could restart a connection or replace newer
state. Controller guards now invalidate those attempts and ignore stale errors
and completion cleanup. This is not proof that these defects caused the user's
specific failed language-switch attempt.

## Candidate Installation

On 2026-09-22, built and installed **1.0.0 (2), Profile** from the working tree
described above, including the background/sync and subtitle repairs. Build
completed in 32.3 seconds; bundle size reported 107.2 MB. Verified the bundle's
`CFBundleVersion` is `2`. `devicectl` reported successful installation and launch
at 15:19:48 Asia/Taipei on the connected iPhone 14 Plus. This was an overwrite
installation, not an uninstall; no user-data deletion was requested.

The build retains the existing personal team and production API, with
`SHOW_APPLE_SIGN_IN=false` only for this device test configuration. It is not
the store distribution configuration. No commit, push or backend deployment
was performed on September 22. At that point actual spoken-language and
audio/subtitle acceptance on build 2 was **NOT RUN**. The September 27 user
follow-up above supersedes that historical state: language switching **FAILED**.

1. **Spoken language switching: FAILED in user testing.** Verify recognized
   command, desired language, accepted revision and next actual audible reply
   separately. Cover Mandarin to Taiwanese and the reverse, polite commands,
   late transcripts, rapid changes and non-command language mentions.
2. **Subtitle/audio timing: UNVERIFIED.** Current pagination uses a reading-speed
   estimate, not audio timestamps. Offline pagination tests cannot certify exact
   synchronization. Preserve manual previous/next controls and all text.
3. **Background/connection recovery: UNVERIFIED on device.** Test lock/unlock,
   background while connecting and speaking, offline/online and stale updates.
4. **Continuous conversation: UNVERIFIED on device.** Complete 20 consecutive
   turns without stuck microphone, duplicate answers or permanent busy state.
   Include short utterances, silence and a long answer.
5. **Authorized end-to-end care workflows: UNVERIFIED this round.** A test
   account must create a reminder/diary and verify the correct authorized web
   view. Private diary entries must remain hidden. Do not use real care data.
6. **Store distribution: NOT VERIFIED.** Device Profile installation does not
   replace the formal team's signed archive/TestFlight and store requirements.

## Reproducible Offline Commands

```sh
flutter test --no-pub test/widgets/pet_subtitle_text_test.dart test/widgets/conversation_bubble_stack_test.dart test/conversation_ui_state_test.dart test/realtime_timeout_test.dart test/realtime_turn_coordinator_test.dart test/screens/login_screen_test.dart --reporter expanded
flutter test --no-pub test/controllers/auth_controller_test.dart test/controllers/agent_tool_controller_test.dart test/services/native_tool_executor_service_test.dart test/services/mood_diary_service_test.dart test/services/check_in_reminder_schedule_test.dart --reporter expanded
flutter test --no-pub --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://ai-companion-api-1gm7.onrender.com test/config/store_readiness_test.dart --reporter expanded
node --test caregiver_web/workspace_loading.test.js caregiver_web/auth_mode.test.js caregiver_web/mood_diary.test.js caregiver_web/daily_task_loading.test.js caregiver_web/caregiver_provisioning_ui.test.js
flutter test --no-pub test/voice_agent_controller_realtime_lifecycle_test.dart test/realtime_language_sync_test.dart test/realtime_voice_service_test.dart test/language_routing_service_test.dart test/voice_language_command_service_test.dart --reporter expanded
flutter test --no-pub test/widgets/pet_subtitle_text_test.dart test/home_screen_layout_test.dart test/widgets/conversation_bubble_stack_test.dart --reporter expanded
```

## Closing the Gate

Record the exact build number, commit plus any working-tree changes, device/iOS,
network and pass/fail result for each device scenario in
`docs/VOICE_LANGUAGE_SMOKE_CR0109.md`. A failed case requires a reproducible
regression test where possible and another run on the same candidate build.
Do not transfer evidence from a previous installation to a changed build.
Do not mark the whole App verified from this focused audit.

## Safe Language Diagnostics

The Profile build adds state-only `VOICE_LANGUAGE` and `VOICE_LANGUAGE_ACK`
events. They contain revision/generation, desired/applied language and state,
not transcript, user identity, token or full instructions. Release logging
remains disabled through `AppLog`.

Use the event sequence to isolate a failed attempt:

- `final_not_command`: the final input did not match an explicit switch command.
- `final_stale_revision`: an older input was rejected after a newer preference.
- `final_command_accepted` then `preference_changed`: parsing and local preference
  change happened; neither proves the service accepted the new instructions.
- ACK `send`, then `matched` and controller `applied`: current revision accepted.
- `ack_timeout`, `send_failed`, `rejected` or `not_applied`: do not report success.
- `next_input_started` and `response_started`: compare desired/applied state,
  then independently judge the actual audible language.

Do not collect full console logs or real resident conversations merely to debug
switching. A matched ACK is still not proof of Taiwanese speech quality.
