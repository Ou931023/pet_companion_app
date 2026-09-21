# Care Workspace Recovery - 2026-09-21

## Confirmed production incident

Render logs identified `column "proof_mime_type" does not exist` in the admin
daily-care-task endpoint. `/health` and CORS preflight succeeded, so the generic
connection error in the browser was misleading.

Applied the existing additive migration 018 to the Neon production database:
`proof_image_bytes BYTEA` and `proof_mime_type TEXT`, both with
`ADD COLUMN IF NOT EXISTS`. No resident records were changed or deleted.
The live task page subsequently loaded three tasks successfully.

## Frontend corrections

- Workspace sections load independently, with bounded requests and specific
  section failures; unavailable counts stay unknown rather than becoming zero.
- Authentication changes invalidate pending workspace and task responses.
- Tasks resolve names from the authorized resident endpoint. Unsubmitted tasks
  no longer show empty AI judgement fields.
- Updated the script cache version.

## Verification

- 74 targeted Flutter tests passed: subtitles, realtime turn coordination,
  timeout policy, voice lifecycle, daily task API, mood diary API.
- Web regression tests cover partial failure, authentication expiry, stale
  requests, timeout cleanup, response shapes and task presentation.
- This is not proof of complete App Store readiness or end-to-end microphone
  quality. A real-device conversation, permission and account lifecycle smoke
  run is still required before submission.

## Remaining release control

Production deployment must run reviewed database migrations before serving code
that needs them. Render currently starts `node server.js` without a visible
migration stage; migration 018 had been omitted despite successful deployments.
Do not equate a healthy process with a compatible database schema.
