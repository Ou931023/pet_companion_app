# Offline model migration — 2026-10-15

Status: proposed defaults, draft review only. Original offline verification performed no paid inference or production changes. Subsequent user-reported PR57 smoke and estimated nonzero spend are recorded in [text release readiness](TEXT_RELEASE_READINESS_20261015.md); they do not approve this full migration. Baseline: `62682854220f8e4cb50fc75842ff3f97e8974b13`.

## Request inventory and compatibility

| Path | Selection precedence | New default / output budget |
| --- | --- | --- |
| Companion text chat | COMPANION_CHAT_MODEL, MEMORY_MODEL | gpt-6-luna / existing 220 tokens |
| Active memory extractor | MEMORY_EXTRACT_MODEL | gpt-6-luna / 2048 tokens |
| Legacy memory extractor | MEMORY_MODEL | gpt-6-luna / 2048 tokens |
| Legacy AI memory greeting | MEMORY_MODEL | gpt-6-luna / 256 tokens |
| Conversation title | CONVERSATION_TITLE_MODEL | gpt-6-luna / 128 tokens |
| Search summarizer | SEARCH_SUMMARY_MODEL, MEMORY_MODEL | gpt-6-luna / 768 tokens |
| Tavily summarizer | WEB_SEARCH_SUMMARY_MODEL, MEMORY_MODEL | gpt-6-luna / 768 tokens |
| Daily-care image verification | injected model, DAILY_CARE_VISION_MODEL | gpt-6-luna / 1024 tokens |
| Completed audio upload | STT_MODEL (new) | gpt-transcribe / existing upload limits |
| GA WebRTC call and health model name | REALTIME_MODEL | gpt-realtime-2.1 / 1024 output tokens, low reasoning |
| Legacy beta session | LEGACY_REALTIME_MODEL (new) | gpt-realtime, unchanged beta parameters |
| GA in-session transcription | fixed, unchanged | gpt-4o-transcribe, language zh |
| Beta in-session transcription | fixed, unchanged | gpt-4o-mini-transcribe, existing prompt |

The active deterministic memory greeting, embeddings (`text-embedding-3-small`), weather provider and separate Taigi ASR are unchanged. No schema, source-turn uniqueness, API shape, transport, VAD, authentication or alert changes. Existing records require no migration or deletion.

Luna uses Chat Completions, `reasoning_effort: none`, `max_completion_tokens`, existing temperatures and existing JSON mode where applicable. This matches the prior non-reasoning workload; medium is not an acceptable accidental default. Low is only a later controlled evaluation candidate: remove temperature when testing it and account for reasoning tokens within the completion budget. Existing non-Luna overrides retain previous parameter shapes, including `max_tokens` for chat. Arbitrary overrides are operator responsibility, not a claim of compatibility with every model.

All affected completion consumers reject `finish_reason: length`, `content_filter` or a nonempty refusal before parsing or accepting content, including parseable-but-truncated JSON. They use existing failure paths: chat unavailable, image uncertain/manual review, title/greeting fallback, source-grounded search fallback or existing search error, and guarded memory fallback. Missing finish_reason remains compatible with existing responses/mocks. This does not relax the active memory source validator. For chat only, newly rejected nonempty completions retain the baseline authorized user-text risk side-recording before the unchanged 503 response, using a backend-only marker. Empty completions and pre-existing provider/key/network failures retain their prior early-return behavior. No rejected content is returned or used for risk classification; rules, cooldown and recipients are unchanged.

`STT_LANGUAGES` is an optional comma-separated allowlist (`zh`, `zh-tw`, `cmn`, `en`), deduplicated into `languages`; omission leaves autodetection. Unsupported hints fail through the existing upload error/cleanup path. Do not assume Hokkien `nan` support. Never send both `language` and `languages`. Legacy STT overrides omit the new hints. The installed, locked OpenAI JavaScript SDK 4.104.0 forwards the JSON fields and serializes `languages[]` multipart parts: tested by intercepting fetch without network. No SDK upgrade is required for these JavaScript paths; this is wire-format evidence, not provider acceptance or entitlement evidence.

GPT-Transcribe's committed-turn Realtime workflow requires WebSocket. This app uses WebRTC, so its in-session transcription cannot safely adopt that model in this change. Beta is isolated because new-model support for the old session API is not established. **REALTIME_MODEL now controls GA only**: operators relying on a custom beta model must explicitly use LEGACY_REALTIME_MODEL. Neither endpoint's response shape changes.

## Evidence and release gates

Offline checks cover installed-SDK serialization; caller defaults and legacy overrides; JSON/image/source contracts; complete, malformed, throwing, truncated, filtered and refused replies; upload abort/cleanup; GA/beta session bodies and upstream failures. The memory content matrix runs 68 synthetic fixtures in 16 provider modes, through HTTP, persistence stub, embedding input, context and greeting, with one record per source turn. No real user records or paid providers are used.

Before release: independent parent review of the exact diff; full backend and exact-commit CI success; an operator review of the allowlisted model settings (never copy secrets); account/model access and synthetic quality evaluation; explicit deployment target/revision verification. Catalog availability does not establish account entitlement. Existing environment overrides may prevent new defaults from taking effect. Local tests do not establish latency, speech quality, interruption handling, live model JSON reliability or iOS device behavior.

## Minimum synthetic paid evaluation proposal — NOT EXECUTED

Use an already authorized OpenAI project/key injected by its operator into an isolated test environment. Do not inspect/copy production secrets. If that project lacks access, request access or retain old models; do not create a paid service, new key or persistent permission implicitly. An existing configured deployment is an alternative only with an approved synthetic-only canary and alert/storage isolation; offline mocks alone remain the available option until these conditions are met.

Propose a **US$2 total stop budget**, requiring separate approval and actual usage tracking; this estimate is not a provider-enforced spending cap. Run sequential small batches and stop if projected next-batch cost exceeds the remainder. Do not run if usage/cost cannot be measured.

1. Text: reuse the 68 memory fixtures plus short chat/title/search cases; compare none vs low on a small representative subset, not all cases twice. Include source ownership, temporary refusal, uncertain/cancelled/future facts, safety refusals, valid JSON, no invented sources, clipped completion and empty output. A 400k input/100k total output-token envelope costs approximately $0.09 at Luna standard rates; reasoning consumes output tokens. Keep prompts below the long-context pricing threshold.
2. Image: 6 synthetic object fixtures (clear, blurry, absent and ambiguous); never infer medication consumption from an object photograph. Include their actual image-token usage in the text envelope; stop if it does not fit.
3. Recorded STT: up to 10 synthetic/consented non-resident minutes across Mandarin, Taiwan Mandarin, mixed English and Taiwanese-accented speech. At $0.0045/min, approximately $0.045. Evaluate meaning and negation, not invented Hokkien support.
4. Realtime: at most three short consented synthetic WebRTC sessions, bounded to 3 total minutes with controlled output, interruption and reconnect tests. Audio rates are $32/M input and $64/M output tokens; text rates are $4/M input and $24/M output. Duration alone is not a reliable token-cost cap. Stop after each measured session; retain the remaining budget for retries only after identifying their cause.

Accept only if memory provenance/negation/temporal gates have zero regressions, image ambiguity remains uncertain, source citations remain grounded, and measured latency/turn-taking fit the app's current baseline. Otherwise retain old models or revise caps in another reviewed change. No quality claim follows from offline mocks.

## Rollback and deployment

Revert this PR for exact prior behavior. No data rollback is needed. For targeted configuration rollback, use `gpt-4o-mini` for COMPANION_CHAT_MODEL, MEMORY_EXTRACT_MODEL, MEMORY_MODEL, CONVERSATION_TITLE_MODEL, SEARCH_SUMMARY_MODEL, WEB_SEARCH_SUMMARY_MODEL and DAILY_CARE_VISION_MODEL; use `gpt-4o-transcribe` for STT_MODEL and `gpt-realtime` for REALTIME_MODEL. Set LEGACY_REALTIME_MODEL to the previously used beta override if relevant. Configure values through the authorized operator, never a committed env file. No settings were read or changed during this task.

After any separately approved release, verify actual deployed commit and allowlisted model selections; public health only confirms the selected GA name, not inference quality or account access. Perform synthetic smoke checks without production care alerts. Restore overrides/revert if errors, latency or quality regress. iOS signing/profile renewal remains separate and was not attempted.

## Official references checked on 2026-10-15

- [GPT-6 Luna model, modalities and pricing](https://developers.openai.com/api/docs/models/gpt-6-luna)
- [GPT-6 migration and reasoning/sampling compatibility](https://developers.openai.com/api/docs/guides/latest-model/gpt-6-astra)
- [Chat completion parameters](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
- [GPT-Realtime 2.1 model and pricing](https://developers.openai.com/api/docs/models/gpt-realtime-2.1)
- [GA create-call session schema](https://developers.openai.com/api/reference/resources/realtime/subresources/calls/methods/create)
- [Realtime conversations and WebRTC](https://developers.openai.com/api/docs/guides/realtime-conversations)
- [GPT-Transcribe model](https://developers.openai.com/api/docs/models/gpt-transcribe)
- [Recorded audio and language hints](https://developers.openai.com/api/docs/guides/speech-to-text)
- [Realtime transcription transport constraints](https://developers.openai.com/api/docs/guides/realtime-transcription)
