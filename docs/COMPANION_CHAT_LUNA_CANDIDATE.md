# Companion chat Luna compatibility candidate

Refreshed 2026-10-25 onto main `7615a61221cb627babdaf0af4fae142570046e0e`, which includes PR57 and PR68. This candidate does not merge PR55 or PR59. Model defaults and production settings remain unchanged. This document does not authorize paid evaluation or model activation.

## Runtime scope and compatibility

Only `companionChatService.js` and the `/api/companion/chat` failure path in `server.js` change. Exact `gpt-6-luna` sends `reasoning_effort: none`, `max_completion_tokens: 220` and existing temperature 0.6. Default remains `gpt-4o-mini`; precedence remains COMPANION_CHAT_MODEL, then MEMORY_MODEL, then default. Other models keep `max_tokens`; prompt/history sanitization is unchanged. The exact model alias is intentional; unreviewed snapshot/custom aliases do not silently opt in.

For both old and Luna models, length/content_filter/nonempty refusal metadata now reject content instead of returning an incomplete response. This is a real behavior change even without activation. Only rejected **nonempty** content that previously reached authorized user-text risk processing gets an internal marker: the route preserves that same processing then returns the existing 503 error shape, without reply/marker/alert detail. Empty content, missing key, invalid input and provider exceptions retain their prior early-return semantics. No change to authorization, risk classification, consent, cooldown, recipient or notification transport. All regression notifications use spies.

No changes to other text consumers, memory extraction/persistence/embedding, Vision, uploads/STT, GA/beta Realtime, frontend, SDK/dependencies, schema or production settings. Existing data needs no migration. Existing memory tests remain in the full suite as regression coverage, not as a claim of changed memory behavior.

## Target and rollback

Deployment target: existing Render My Workspace API `srv-da44a1btqb8s7382sp00`, main branch, root `backend/stt_proxy`, npm install / node server.js. The previous preparation revision is historical; verify each release against the actual deployment commit and public /health revision. No environment values or model account access are inspected by this candidate.

Before any future deployment: verify the reviewed exact commit and current override values, account access and quality gates. A later activation should change only COMPANION_CHAT_MODEL, never the shared MEMORY_MODEL. Restore the prior chat override to reverse model activation; revert this candidate or redeploy the verified previous revision to also reverse the new completion guard. No database rollback/deletion. Public health alone cannot reveal the companion model; use approved allowlisted configuration verification plus a controlled synthetic check. Never send alert-triggering tests through production routes.

## Evidence and limits

Approved public historical record: one user-executed PR57 batch used 88 input tokens and 41 output tokens; actual billed amount is unconfirmed. That batch must not be repeated and does not validate this application's prompt, 220-token budget or quality. This refresh adds no paid call.

Offline tests cover actual SDK 4.104.0 serialization for default/legacy/Luna/custom models, history and prompt forwarding, explicit budgets, old/Luna rejection metadata, actual route model precedence/persona/memory context, and authorized/unauthorized/cross-resident/ordinary/empty risk side-recording. Existing persona, consent/cooldown, language and disclaimer tests remain applicable. Windows HTTP tests require approved localhost access; child-process tests need dependencies installed in this worktree, not merely inherited NODE_PATH.

## Minimum quality comparison proposal — NOT IMPLEMENTED OR EXECUTED

First review two new synthetic app-shaped cases, each compared once with the current confirmed baseline and once with Luna: at most **four sequential requests**, no retry, tool, streaming or parallel run. If baseline is not gpt-4o-mini, recalculate before proceeding. Build request fixtures offline by capturing this branch's actual `buildCompanionChatInstructions` route output through a fake SDK (never load server.js on Render); verify the frozen fixture hash against the candidate commit. Use actual temperature 0.6 / 220 cap, Luna none, and existing sanitized history. Do not reuse the generic PR57 prompts.

1. Temporary boundary and independent fact: synthetic memory says the user likes walking and has a daughter; current turn says “我喜歡散步，但今天不聊女兒，陪我聊花吧”. Require a short Traditional Chinese reply about flowers/walking without probing family or inventing facts.
2. Uncertain plan cancelled in history: user previously said “我可能下個月搬去台中”; later “不搬了，還住原處”; current turn “明天再想想要去哪裡散步”. Require no assertion that a move happened or is scheduled, no invented address and no treatment of tomorrow's thought as a completed fact.

Review naturalness, factual grounding, topic boundaries, valid nonempty completion, finish/refusal status and elapsed time. A failure stops the batch; timeout is potentially billed. These two cases are a small first quality checkpoint, not comprehensive quality/latency assurance or automatic permission to release. Broader cases require a separately reviewed remaining-budget plan; no unbounded repetitions to obtain a passing sample.

Historical proposal only, not current pricing or execution approval. Budget basis checked 2026-10-15: [Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) input/cache-write maximum $0.125/M, output $0.50/M, context 1.05M; conservatively include long-context input 2x/output 1.5x, Fast 2x and regional 1.1x, despite small inputs/default tier. Two Luna requests at 220 output each: `2 * (1.05 * .125 * 2 * 2 * 1.1 + 220/1e6 * .50 * 1.5 * 2 * 1.1) = $1.155726`.

[gpt-4o-mini](https://developers.openai.com/api/docs/models/gpt-4o-mini) documents 128K context and $0.15/M input, $0.60/M output. Two standard-tier requests at full context plus 220 output: `2 * (128000/1e6*.15 + 220/1e6*.60) = $0.038664`. Proposed batch standard-price ceiling under these assumptions: **$1.194390**. No tax, custom pricing, unrelated traffic or unknown prior charges included. These are published-price bounds, not provider account caps. The model page labels gpt-4o-mini deprecated; verify continued account availability without silently substituting a model or expanding scope.

Do not execute until the previous charge/remaining overall $2 budget is reconciled, settings and applicable rates are confirmed, exact fixtures and bounded runner are independently reviewed, and the operator authorizes that execution path. This candidate contains no new live evaluator. Full offline suite/exact-head CI, parent diff review and later quality/deployment gates remain required.

Current local validation on 2026-10-25: clean locked install, focused 63/63, full backend 1020/1020, offline 70/70, syntax and diff checks passed; audit 9 moderate, 0 high/critical. These results precede final integration of PR57; final exact-tree CI and independent review remain required. Earlier preparation counts are historical, not fresh release evidence. No paid calls or model activation.

## Refreshed test isolation

Before loading server, HTTP tests replace pg.Pool with a query/connect-rejecting fake, force default availability offline and inject offline persistence/audit seams. A global fetch fence permits only loopback; Telegram is separately intercepted at the exact synthetic URL. Teardown restores seams/mocks and asserts zero SQL, PG IO or unexpected outbound attempts. A synthetic poison DATABASE_URL run verifies inherited settings cannot reach a real DB.
