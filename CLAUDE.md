# Project: AI Elderly Companion Pet App

## Project Goal
This is a graduation project for an Information Management department.
The app is an AI elderly companion pet app. The core goal is not just chatbot Q&A, but emotional companionship through voice interaction, long-term memory, and a virtual pet UI.

## Tech Stack
- Frontend: Flutter
- Mobile target: iPhone real device
- Backend: Node.js
- Voice: OpenAI Realtime API with WebRTC
- Memory DB: PostgreSQL + pgvector
- Search: Tavily / trusted source search
- AI features: emotion analysis, companion reply strategy, long-term memory retrieval

## Current Architecture
Frontend:
- Flutter app
- Main voice flow uses WebRTC, not file upload
- Main controller: lib/controllers/voice_agent_controller.dart
- Conversation state: lib/controllers/conversation_controller.dart
- Memory service: lib/services/memory_service.dart
- Language routing: lib/services/language_routing_service.dart

Backend:
- Node.js backend
- Realtime endpoint: POST /api/realtime/call
- Memory endpoints:
  - POST /api/memories/extract
  - POST /api/memories/context
  - POST /api/memories/:id/archive
- Taigi ASR endpoints may exist, but do not change them unless explicitly requested.

## Important Constraints
- Do not rewrite the whole project.
- Do not change the Realtime WebRTC main flow unless explicitly requested.
- Do not remove existing tests.
- Prefer minimal, safe, incremental changes.
- Do not add demo-only fallback messages.
- Do not show debug/dev messages in user-facing UI.
- Keep the app presentation-ready for a graduation project demo.
- When modifying code, explain changed files and run relevant tests if possible.

## Current Priorities
1. Make the app stable enough to run on iPhone.
2. Make Realtime voice conversation reliable.
3. Make long-term memory work visibly in the demo.
4. Make the UI clean and presentation-ready.
5. Avoid large refactors unless necessary.

## Coding Style
- Keep changes small.
- Add or update tests when modifying core logic.
- Use clear Traditional Chinese UI text.
- Avoid breaking existing APIs between Flutter and Node.js.