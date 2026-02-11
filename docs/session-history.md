# Session History

> Archived session notes for the Astute project. See [CLAUDE.md](../CLAUDE.md) for the current project state.

## Session 1 (prior)

Built Astute from scratch — OpenAI Realtime API, WebRTC, Porcupine wake word, greeting feature, VAD tuning.

## Session 2 (prior)

Extracted code into AstuteVoiceEngine Swift Package, pushed to GitHub, refactored Astute to consume it, fixed weak delegate bug, renamed repo.

## Session 3 (2026-02-09)

- Made package cross-platform (iOS + macOS): MicrophonePermissions, WakeWordEngine, WakeWordConfiguration
- Bundled `PvPorcupine.xcframework` for iOS
- Fixed Info.plist build conflict, macOS dylib linking on iOS, duplicate user messages
- Added iOS-specific UI (list section with status and new conversation button)
- Confirmed voice conversations work on physical iPhone

## Session 4 (2026-02-09)

- Removed Porcupine wake word detection entirely (cost/complexity decision)
- Removed AstuteWakeWord, CPorcupine, PvPorcupine from package
- Removed .ppn files, libpv_porcupine.dylib, Frameworks directory from app
- Cleaned up ContentView, ConversationView, SettingsView, KeychainHelper, project.pbxproj
- App now uses button-only activation for voice conversations

## Session 5 (2026-02-10)

- Reviewed architecture: confirmed app is a thin UI/data layer (~720 lines), package handles all voice/WebRTC logic (~1,067 lines)
- Removed AstuteVoiceEngineUI library from package (VoiceChatBubble, VoiceControlBar, VoiceConversationView) — each consuming app owns its own UI
- Package now exports only `AstuteVoiceEngine` (core engine, no UI)
- Refactored RealtimeConnection.swift:
  - Replaced all print() with os.log (Logger subsystem: com.astute.voiceengine)
  - Replaced forced unwraps (!) in createPeerConnection with guard/throw
  - Extracted MessageTracker struct for per-turn state (transcription, AI response, emitted flag)
  - Broke 130-line processServerEvent switch into 11 dedicated handler methods
  - Refactored reconnection: iterative loop (not recursive), 30s delay cap, deduplication guard
  - Wired up onError callback → delegate.didEncounterError() (was defined but never called)
  - Added alreadyConnected guard to connect()
  - Added notConnected guard to updateInstructions()
  - Fixed flushPendingMessages to also reset isUserSpeaking/isAIResponding
  - All JSON parse failures now logged instead of silently dropped
- Added 8 unit tests for MessageTracker (including duplicate emission prevention regression test)
- Removed dead testWakeWordConfigurationDefaults stub

## Session 6 (2026-02-10)

- Major refactor: extracted WebRTC into `TransportProvider` protocol + `WebRTCTransport` concrete implementation
- `RealtimeConnection` no longer imports WebRTC — delegates all transport concerns via protocol
- Replaced 5 independent boolean `@Published` properties (`isConnected`, `isSessionActive`, `isUserSpeaking`, `isAIResponding`, `isGreeting`) with two enums: `ConnectionState` and `ConversationPhase`
- VoiceEngine maps enums to boolean `@Published` properties via Combine `.map` — public API unchanged
- Made API endpoint, ICE servers, reconnect attempts, and reconnect delay configurable in `VoiceEngineConfiguration`
- Added `IceServer` struct supporting STUN and TURN (username/credential)
- Created `MockTransport` test double for deterministic unit testing
- Added 35 `RealtimeConnectionTests` covering: connection lifecycle, session lifecycle, speech flow, message ordering, duplicate user message prevention, greeting (mic mute/unmute), text messages, barge-in, flush pending, error handling, reconnection, mic muting, AI response accumulation, update instructions
- Updated existing config tests for new properties
- Total: 49 tests, 0 failures
- Astute app builds with zero source changes (BUILD SUCCEEDED)
- Fixed logic bug in `handleSpeechStarted()` — was setting phase to `.userSpeaking` before checking previous phase for greeting/barge-in

## Session 7 (2026-02-10)

- Created **AstuteMemory** Swift Package (new repo: `https://github.com/dlarmitage/AstuteMemory`)
  - `ConversationSnapshot` and `MessageSnapshot` protocols — framework-agnostic (no SwiftData dependency)
  - `ContextBuilder` — pure function that builds system instructions enriched with past conversation summaries and current transcript
  - `Summarizer` — generates 2-3 sentence conversation summaries via `gpt-4o-mini` Chat Completions
  - `TitleGenerator` — generates 3-6 word conversation titles via `gpt-4o-mini`
  - `ChatCompletionsClient` — lightweight REST client for OpenAI Chat Completions API
  - `TranscriptFormatter` — internal helper formatting messages into plain-text transcripts
- Integrated AstuteMemory into Astute app:
  - `Conversation` model: added `summary: String?` and `isTitleGenerated: Bool` fields, conforms to `ConversationSnapshot`
  - `ConversationMessage` conforms to `MessageSnapshot`
  - `ConversationView`: injects conversation context via `ContextBuilder.buildInstructions()` before each `voiceEngine.start()` call
  - Summary and title generated in background `Task.detached` on `onDisappear`
  - Title auto-fill from first message is now a temporary placeholder until AI generates a proper title
  - `ContentView`: added `.searchable` filtering by title and summary; `ConversationRow` shows summary preview
  - `project.pbxproj`: added `AstuteMemory` local package reference
- Reorganized project documentation:
  - CLAUDE.md restructured: added Coding Conventions, Testing Expectations, checkbox TODOs, condensed session history with link to archive
  - Added README.md for the Astute app (features, getting started, architecture)
  - Extracted session history to `docs/session-history.md`
  - Extracted sherpa-onnx research to `docs/sherpa-onnx-research.md`
  - Added README.md to AstuteVoiceEngine package
