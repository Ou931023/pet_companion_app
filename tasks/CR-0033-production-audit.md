# CR-0033 — Production Audit

## 0. Task Metadata

- CR ID: CR-0033
- Title: Production Audit
- Type: Audit / Planning / Low-risk cleanup only
- Priority: Critical
- Target: Upgrade the project from graduation-project demo quality to production-ready quality for iOS App Store and Google Play readiness.
- Scope: Flutter elder app, Node.js backend, caregiver_web, database layer, documentation, environment configuration, tests, release/build settings.

---

## 1. Background

This project is an AI Pet Companion System for elderly care. The system is intended to become a formal production-ready product, not a demo.

The system described in the paper includes:

1. Flutter elder-facing mobile app.
2. Node.js / Express backend.
3. OpenAI Realtime API + WebRTC for near real-time voice interaction.
4. PostgreSQL + pgvector for long-term memory.
5. Emotion analysis and risk detection.
6. Four-level Care Alert: low / medium / high / urgent.
7. Telegram notification for authorized caregivers.
8. Caregiver / long-term-care management web dashboard.
9. Taiwanese / Mandarin mixed-language support.
10. Trusted-source health / anti-fraud information behavior.
11. Privacy, informed consent, data governance, and user control over memory.

The current project may still contain demo-only logic, mock data, JSON fallback, development-only UI, hardcoded test data, or unfinished production gates. This task must identify those issues before production refactoring begins.

---

## 2. Main Goal

Perform a full production-readiness audit of the entire codebase.

Do not start large refactors in this CR.

This CR is mainly for:

1. Discovering all demo / mock / fallback / debug risks.
2. Classifying production blockers.
3. Creating a clear remediation plan for CR-0034 and later.
4. Applying only very low-risk cleanup when safe.
5. Updating `docs/CHANGE_REVIEW.md` with concrete audit results.

---

## 3. Non-Negotiable Production Principles

The final production version must not rely on:

1. demo-only flow.
2. fake transcript.
3. fake AI response.
4. mock user / mock caregiver / mock resident as production data.
5. hardcoded admin token.
6. hardcoded Telegram chat ID.
7. hardcoded OpenAI API key.
8. hardcoded database credentials.
9. local JSON files as production database.
10. visible debug panel in production UI.
11. engineering error messages shown to elderly users.
12. `Demo`, `Test`, `Mock`, `Dev`, `Debug`, `測試`, `示範`, `開發中` wording in production-facing UI.
13. hidden fallback that pretends production functionality succeeded.
14. medical diagnosis wording for Care Alert or health-related responses.
15. unconsented collection of conversation, voice, memory, or care-risk data.

---

## 4. Required Audit Scope

Audit all relevant files and directories. At minimum, inspect these areas if they exist:

### 4.1 Flutter App

Look for:

- demo screens
- debug panels
- fake / mock services
- hardcoded users
- hardcoded residents
- local-only authentication
- fake login
- fake transcript
- fake AI response
- fake memory
- fake Care Alert
- `SHOW_DEV_PANELS`
- `ALLOW_MOCK_SERVICES`
- `ALLOW_JSON_FALLBACK`
- `kDebugMode` leakage into user-facing UI
- debug banner
- user-facing technical errors
- permission flows for microphone / notification / camera / gallery
- privacy policy / terms / consent entry points
- logout and account deletion entry points
- local storage of sensitive data
- Realtime state and error handling
- Taiwanese / Mandarin mode fallback behavior
- pet skin persistence
- reminder notification implementation
- game-result persistence

Suggested search terms:

```bash
rg -n "demo|Demo|DEMO|mock|Mock|MOCK|fake|Fake|FAKE|debug|Debug|DEBUG|dev|Dev|DEV|test|Test|TEST|fallback|Fallback|FALLBACK|hardcoded|TODO|FIXME|HACK|temporary|temp|測試|示範|開發中|假資料|假|除錯" lib test integration_test ios android .
```

Also inspect `.dart` files manually after keyword search.

### 4.2 Node.js Backend

Look for:

- demo route
- mock route
- fake response
- fake transcript
- fake OpenAI response
- JSON data store used as production fallback
- hardcoded token
- hardcoded Telegram chat ID
- hardcoded admin token
- missing production config validation
- permissive CORS in production
- stack trace returned to frontend
- sensitive logs
- raw transcript logs
- full email / phone logs
- missing auth on admin APIs
- missing role-based access control
- missing resident-caregiver authorization checks
- missing audit log on sensitive operations
- Care Alert classification inconsistencies
- legacy risk-level names
- notification cooldown logic
- notification failure handling
- memory cross-user leakage risk
- pgvector disabled by default in production

Suggested search terms:

```bash
rg -n "demo|Demo|DEMO|mock|Mock|MOCK|fake|Fake|FAKE|debug|Debug|DEBUG|fallback|Fallback|FALLBACK|json|JSON|hardcoded|TODO|FIXME|HACK|temporary|temp|admin token|telegram|chat_id|OPENAI_API_KEY|DATABASE_URL|stack|console\.log|測試|示範|假資料" backend .
```

### 4.3 Caregiver Web

Look for:

- fake dashboard data
- local-only user list
- mock alerts
- hardcoded admin token
- unprotected admin pages
- missing auth headers
- missing role checks
- unmasked personal data
- full email / phone shown unnecessarily
- no loading / error states
- demo wording
- debug UI
- incomplete alert status flow
- no resident authorization boundary
- missing emotion history or production API wiring
- missing game-decline indicator wiring

Suggested search terms:

```bash
rg -n "demo|Demo|mock|Mock|fake|Fake|debug|Debug|test|Test|fallback|hardcoded|TODO|FIXME|admin|token|email|phone|alert|resident|caregiver|測試|示範|假資料" caregiver_web .
```

### 4.4 Database / Persistence

Look for:

- JSON fallback as primary data source
- missing migrations
- incomplete PG schema
- missing pgvector extension setup
- missing indexes
- missing user_id / resident_id boundary
- memory records not bound to user/resident
- Care Alert not bound to resident
- notification not bound to caregiver authorization
- consent not stored
- deletion requests not stored
- audit logs missing

Check for files like:

- `data/*.json`
- `backend/**/store*`
- `backend/**/repository*`
- `backend/**/memory*`
- `backend/**/careAlert*`
- migration folders
- SQL files

### 4.5 Documentation

Inspect:

- `CLAUDE.md`
- `README.md`
- `docs/CHANGE_REVIEW.md`
- `docs/PROJECT_ARCHITECTURE.md`
- `docs/TEAM_AGENTS.md`
- `.env.example`
- deployment docs
- API docs
- privacy docs if present
- store release docs if present

Look for:

- outdated demo language
- claims inconsistent with production status
- missing privacy / data governance docs
- missing store-readiness checklist
- missing environment setup docs
- missing test instructions
- missing production deployment instructions

### 4.6 Build / Release Settings

Inspect:

- `pubspec.yaml`
- iOS bundle settings
- Android applicationId
- app icon settings
- launch screen
- release signing docs
- microphone permission text
- notification permission text
- camera/gallery permission text if used
- debug banner removal
- build flavors if present
- production environment selection

---

## 5. Risk Classification

Classify every finding using this severity system:

### P0 — Production Blocker

Must be fixed before any release candidate.

Examples:

- hardcoded API key or token
- production uses fake data
- production uses JSON fallback as main database
- unauthenticated admin API
- cross-user memory leakage
- Care Alert sent to wrong caregiver
- no consent before recording/storing sensitive data
- app cannot build release
- Realtime core broken
- crash on startup

### P1 — High Risk

Must be fixed before public store submission.

Examples:

- debug UI visible to users
- demo wording in formal UI
- missing account deletion entry
- incomplete privacy explanation
- technical errors shown to elderly users
- notification cooldown missing
- sensitive data in logs
- missing role check on some caregiver APIs

### P2 — Medium Risk

Should be fixed before real long-term-care field trial.

Examples:

- incomplete management analytics
- weak loading/error states
- missing audit log on some operations
- poor accessibility
- incomplete trusted-source behavior
- game indicator not yet connected to dashboard

### P3 — Low Risk

Can be scheduled after RC if not user-facing or safety-critical.

Examples:

- minor wording polish
- code organization issue
- non-critical TODO
- low-priority doc cleanup

---

## 6. Allowed Changes in This CR

This CR should mostly audit and document.

Allowed low-risk changes:

1. Remove obvious production-facing demo wording if it does not affect logic.
2. Mask obviously unsafe logs if trivial.
3. Add comments marking dev-only code if no logic changes are needed.
4. Update docs.
5. Add TODO entries to production audit checklist.
6. Add missing `.env.example` descriptions only if safe.

Not allowed in this CR:

1. Large auth rewrite.
2. Large database migration rewrite.
3. Replacing Realtime architecture.
4. Rewriting Care Alert classifier.
5. Removing JSON fallback entirely without a follow-up plan.
6. Removing features because they look unfinished.
7. Introducing fake success paths.
8. Changing API contracts without tests.

---

## 7. Required Output Files

Create or update the following:

### 7.1 Required

- `docs/CHANGE_REVIEW.md`

Add a new CR-0033 section.

### 7.2 Strongly Recommended

If not already present, create:

- `docs/PRODUCTION_AUDIT_CR0033.md`

This file should contain the full audit result.

---

## 8. Required Audit Report Format

In `docs/PRODUCTION_AUDIT_CR0033.md`, use this structure:

```md
# CR-0033 Production Audit Report

## 1. Executive Summary

- Overall readiness:
- Number of P0 findings:
- Number of P1 findings:
- Number of P2 findings:
- Number of P3 findings:
- Biggest production blockers:

## 2. Audit Method

List commands and manual inspection areas.

## 3. Findings by Severity

### P0 — Production Blockers

| ID | Area | File / Path | Finding | Why It Blocks Production | Recommended Fix |
|---|---|---|---|---|---|

### P1 — High Risk

| ID | Area | File / Path | Finding | Risk | Recommended Fix |
|---|---|---|---|---|---|

### P2 — Medium Risk

| ID | Area | File / Path | Finding | Risk | Recommended Fix |
|---|---|---|---|---|---|

### P3 — Low Risk

| ID | Area | File / Path | Finding | Risk | Recommended Fix |
|---|---|---|---|---|---|

## 4. Findings by System Area

### 4.1 Flutter Elder App

### 4.2 Backend

### 4.3 PostgreSQL / pgvector / Persistence

### 4.4 Caregiver Web

### 4.5 Notification / Telegram

### 4.6 Realtime Voice

### 4.7 Memory

### 4.8 Emotion / Care Alert

### 4.9 Privacy / Consent / Data Deletion

### 4.10 Store Readiness

### 4.11 Documentation

## 5. Demo / Mock / Fake Data Inventory

| File / Path | Type | Current Behavior | Production Risk | Follow-up CR |
|---|---|---|---|---|

## 6. JSON Fallback Inventory

| File / Path | Data Type | Used In | Production Risk | Recommended Production Replacement |
|---|---|---|---|---|

## 7. Debug / Dev UI Inventory

| File / Path | UI / Flag | Visible in Production? | Risk | Fix |
|---|---|---|---|---|

## 8. Hardcoded Sensitive / Identity Data Inventory

| File / Path | Data | Risk | Fix |
|---|---|---|---|

Do not paste real secrets into this report. Mask them.

## 9. Production Environment Gaps

- Missing env validation:
- Missing build flavor:
- Missing production flags:
- Missing deployment docs:

## 10. Privacy and Data Governance Gaps

- Consent:
- Memory control:
- Account deletion:
- Data deletion:
- Audit log:
- Third-party AI disclosure:

## 11. App Store / Google Play Gaps

- iOS:
- Android:
- Store metadata:
- Privacy policy:
- Data safety:

## 12. Recommended Fix Order

1. CR-0034:
2. CR-0035:
3. CR-0036:
4. CR-0037:
5. CR-0038:
6. CR-0039:
7. CR-0040:
8. CR-0041:
9. CR-0042:
10. CR-0043:
11. CR-0044:
12. CR-0045:
13. CR-0046:
14. CR-0047:

## 13. Tests Run

| Command | Result | Notes |
|---|---|---|

## 14. Files Changed in CR-0033

- 

## 15. Remaining Risks

- 
```

---

## 9. Required `docs/CHANGE_REVIEW.md` Entry Format

Append this section:

```md
## CR-0033 — Production Audit

### Goal
Audit the entire project for production-readiness risks before converting the graduation-project demo into a formal App Store / Google Play ready system.

### Summary
- 

### Key Findings
- P0:
- P1:
- P2:
- P3:

### Files Created / Updated
- docs/PRODUCTION_AUDIT_CR0033.md
- docs/CHANGE_REVIEW.md

### Tests / Commands Run
- 

### Production Blockers Identified
- 

### Recommended Next CR
CR-0034 — Production Environment and Config
```

---

## 10. Commands to Run

Run whatever is safe and available.

Suggested commands:

```bash
pwd
find . -maxdepth 3 -type f | sort | sed 's#^./##' | head -300
rg -n "demo|Demo|DEMO|mock|Mock|MOCK|fake|Fake|FAKE|debug|Debug|DEBUG|fallback|Fallback|FALLBACK|hardcoded|TODO|FIXME|HACK|temporary|temp|測試|示範|開發中|假資料|除錯" .
rg -n "OPENAI_API_KEY|TELEGRAM|BOT_TOKEN|CHAT_ID|DATABASE_URL|ADMIN_API_TOKEN|JWT|SECRET|PASSWORD|PRIVATE_KEY" .
rg -n "console\.log|print\(|debugPrint|logger|stack|StackTrace" backend lib caregiver_web .
```

If Flutter exists:

```bash
flutter analyze
flutter test
```

If backend package exists:

```bash
cd backend/stt_proxy
npm test
npm run check
npm run lint
```

If caregiver_web has package scripts:

```bash
cd caregiver_web
npm test
npm run build
```

If a command does not exist or fails because of missing local environment, record the exact reason in the report. Do not claim success if it was not run.

---

## 11. Special Checks for This Project

Because this project is for elderly care and AI companionship, pay special attention to:

### 11.1 Medical Safety

Find any wording or code that implies diagnosis.

Bad wording:

- 確診
- 診斷
- 你有憂鬱症
- 你生病了
- 系統判定疾病
- 取代醫師

Preferred wording:

- 照護提醒
- 可能需要留意
- 建議照護人員關心
- 請依實際情況判斷
- 若身體不適，請尋求照護人員或醫療協助

### 11.2 Elderly-Friendly UI

Find:

- small buttons
- technical errors
- English-only error strings
- overflow on small screens
- hidden logout
- unclear microphone state
- confusing onboarding

### 11.3 Caregiver Authorization

Verify whether the project currently prevents:

- caregiver A reading resident B without authorization
- admin APIs being called without admin auth
- Telegram notification going to the wrong chat
- alert details leaking raw sensitive conversation text

### 11.4 Memory Safety

Verify whether:

- memories are scoped by user/resident
- deleted memories are excluded from retrieval
- low-quality memory is filtered
- sensitive memory is handled carefully
- memory is not created before consent

### 11.5 Realtime Integrity

Verify whether:

- Realtime uses true WebRTC flow
- no fake transcript is used in production path
- no fake response is used in production path
- error recovery exists
- OpenAI credentials remain backend-side
- user-facing errors are friendly

---

## 12. Final Response Required From Claude

After finishing this task, reply using this exact structure:

```md
# CR-0033 Complete

## 1. What I did

## 2. Files created / updated

## 3. P0 production blockers

## 4. P1 high risks

## 5. P2 / P3 items

## 6. Tests and commands run

## 7. What I did not change

## 8. Recommended next task
CR-0034 — Production Environment and Config
```

Remember:

- Do not claim production readiness after this CR.
- This CR is an audit, not the final fix.
- Be explicit and honest about anything not verified.
