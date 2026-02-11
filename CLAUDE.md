# Astute - Project Handoff Document

> Last updated: 2026-02-10

## Overview

**Astute** is a macOS + iOS SwiftUI voice conversation app using OpenAI's Realtime API via WebRTC. Users start voice conversations via a button tap. The voice engine has been extracted into a reusable Swift Package (**AstuteVoiceEngine**), and conversation memory (summarization, title generation, cross-session context) lives in a separate package (**AstuteMemory**).

## Architecture

```
Astute (App)                          AstuteVoiceEngine (Swift Package)
├── ContentView.swift                 └── AstuteVoiceEngine (library)
├── ConversationView.swift                ├── VoiceEngine.swift          (public facade)
│   ├── VoiceEngine (from pkg)            ├── RealtimeConnection.swift    (session coordinator)
│   ├── ConversationBridge (delegate)     ├── TransportProvider.swift     (transport protocol)
│   └── AstuteMemory (context/summary)    ├── WebRTCTransport.swift       (WebRTC implementation)
├── SettingsView.swift                    ├── MessageTracker.swift        (turn state machine)
├── KeychainHelper.swift                  ├── VoiceEngineConfiguration.swift
├── Conversation.swift (SwiftData)        ├── VoiceEngineDelegate.swift
└── AstuteApp.swift                       ├── MicrophonePermissions.swift
                                          └── Types.swift (VoiceMessage, VoiceEngineError,
                                                           ConnectionState, ConversationPhase)

AstuteMemory (Swift Package)
├── Types.swift                (ConversationSnapshot, MessageSnapshot protocols)
├── ContextBuilder.swift       (builds instructions with past summaries + current transcript)
├── Summarizer.swift           (2-3 sentence conversation summary via Chat Completions)
├── TitleGenerator.swift       (3-6 word title via Chat Completions)
├── TranscriptFormatter.swift  (internal: messages → "User: ... / Assistant: ..." text)
└── ChatCompletionsClient.swift (lightweight OpenAI Chat Completions REST client)
```

## Key Repositories

| Repo | Remote |
|------|--------|
| Astute (app) | `https://github.com/dlarmitage/astute` |
| AstuteVoiceEngine (package) | `https://github.com/dlarmitage/AstuteVoiceEngine` |
| AstuteMemory (package) | `https://github.com/dlarmitage/AstuteMemory` |

> **Note**: Local paths are machine-specific. On the primary dev machine, repos are under `~/Library/Mobile Documents/com~apple~CloudDocs/xCode/`. The app references both packages via **local** `XCLocalSwiftPackageReference` at `../../AstuteVoiceEngine` and `../../AstuteMemory`.

## Coding Conventions

- **Logging**: Use `os.log` with `Logger` (subsystem: `com.astute.voiceengine`), never `print()`
- **Error handling**: Use `guard`/`throw` patterns, never force unwraps (`!`)
- **Architecture**: Dependency injection via protocols (`TransportProvider`, etc.) — concrete implementations should be the only files importing external frameworks
- **State modeling**: Prefer enums over independent booleans for mutually exclusive states
- **Platform code**: Use `#if os(macOS)` / `#if os(iOS)` for platform-specific paths, keep shared logic in common code
- **Testing**: All new public API needs unit tests. Use mock implementations (e.g., `MockTransport`) for deterministic testing without live connections
- **Naming**: Swift standard conventions — PascalCase for types/protocols, camelCase for properties/methods

## Testing & Build Expectations

Run these before committing changes:

```bash
# AstuteVoiceEngine — build and test (macOS)
cd <AstuteVoiceEngine-path>
swift build
swift test

# AstuteMemory — build and test (macOS)
cd <AstuteMemory-path>
swift build
swift test

# App — macOS build
cd <Astute-app-path>
xcodebuild -scheme Astute -destination 'platform=macOS' -skipPackagePluginValidation build

# App — iOS build
xcodebuild -scheme Astute -destination 'generic/platform=iOS' -skipPackagePluginValidation build
```

- `swift test` must pass with 0 failures before merging
- Both macOS and iOS builds must succeed (`BUILD SUCCEEDED`)
- New features should include tests; bug fixes should include regression tests

## Dependencies

| Package | Version | Source | Purpose |
|---------|---------|--------|---------|
| `stasel/WebRTC` | v140.0.0 | Swift Package (in AstuteVoiceEngine) | WebRTC peer connection, audio transport, AEC |
| AstuteMemory | Local | Swift Package | Conversation summarization, title generation, cross-session context |

## Key Technical Details

### WebRTC + OpenAI Realtime API
- SDP offer/answer exchange at configurable endpoint (default: `https://api.openai.com/v1/realtime`)
- Server-side VAD: threshold 0.8, silence duration 1200ms, prefix padding 200ms
- WebRTC provides automatic acoustic echo cancellation (AEC)
- WebRTC is isolated behind `TransportProvider` protocol — only `WebRTCTransport.swift` imports WebRTC
- ICE servers configurable via `VoiceEngineConfiguration.iceServers` (default: Google STUN; supports TURN)

### Transport Architecture
- `TransportProvider` protocol abstracts all WebRTC concerns (connect, disconnect, sendEvent, mic control)
- `WebRTCTransport` is the concrete implementation (RTCPeerConnection, RTCDataChannel, audio tracks)
- `RealtimeConnection` is the session coordinator — accepts any `TransportProvider` via dependency injection
- `MockTransport` enables comprehensive unit testing without a live WebRTC connection
- State tracked via two enums: `ConnectionState` (disconnected/connecting/connected/sessionActive/error) and `ConversationPhase` (idle/userSpeaking/aiResponding/greeting) — replaces 5 independent booleans
- VoiceEngine maps enums to `@Published` booleans via Combine `.map` for backward compatibility

### AstuteMemory — Conversation Memory System
- **Protocol-based**: `ConversationSnapshot` and `MessageSnapshot` protocols keep the package free of SwiftData — consuming apps conform their models
- **ContextBuilder**: Pure function that builds system instructions enriched with past conversation summaries (up to 5 most recent) and current conversation transcript (up to 20 messages). Injected into VoiceEngine via `updateInstructions()` before each connection
- **Summarizer**: Generates 2-3 sentence conversation summaries via `gpt-4o-mini` Chat Completions (temperature 0.3, max 200 tokens)
- **TitleGenerator**: Generates 3-6 word titles from the first ~6 messages via `gpt-4o-mini` (temperature 0.5, max 20 tokens)
- **ChatCompletionsClient**: Lightweight REST client for OpenAI Chat Completions — separate from the Realtime API used by VoiceEngine
- **Timing**: Context is injected before `voiceEngine.start()` so the initial `session.update` includes memory. Summary and title are generated in a background `Task.detached` on `onDisappear` (after the user leaves the conversation)
- **Data model additions**: `Conversation` gained `summary: String?` and `isTitleGenerated: Bool` fields
- **Search**: ContentView uses `.searchable` to filter conversations by title and summary text; ConversationRow shows summary preview

### Cross-Platform (macOS + iOS)
- `MicrophonePermissions.swift`: Uses `AVCaptureDevice` on macOS, `AVAudioSession.recordPermission` on iOS

### Delegate Pattern
- `VoiceEngine.delegate` is **weak** — consuming app MUST hold a strong reference
- Astute uses `ConversationBridge` class implementing `VoiceEngineDelegate`, stored in `@State private var delegateBridge: ConversationBridge?`
- Bridge persists messages to SwiftData (`Conversation`, `ConversationMessage`)
- Title auto-fill from first user message is now a temporary placeholder until AI generates a proper title on conversation end

### Xcode Project Specifics
- Uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ auto-sync from filesystem)
- `PBXFileSystemSynchronizedBuildFileExceptionSet` excludes `Info.plist` from auto-sync (prevents "multiple commands produce Info.plist" error)
- `XCSwiftPackageProductDependency` entries require `package` back-reference to the `XCLocalSwiftPackageReference`

### API Keys
- Stored in macOS/iOS Keychain via `KeychainHelper.swift`
- OpenAI key: service `com.astute.openai`, account `api_key` (`kSecClassGenericPassword`)
- Viewable in Keychain Access.app (NOT the new Passwords app)
- Same API key is used for both Realtime API (voice) and Chat Completions (memory/summarization)

### Mic Muting During Greeting
- When `startWithGreeting()` is called, the mic is muted to prevent audio tail from bleeding into WebRTC VAD
- Mic is unmuted after greeting completes in `emitAIResponse()`

## Important Bug Fixes Applied

### Duplicate User Messages (fixed 2026-02-09)
**Problem**: On iOS, `conversation.item.input_audio_transcription.completed` sometimes arrives after `response.done`. The `emitAIResponse()` function was resetting `userMessageEmitted = false`, causing a late transcription event to call `emitUserMessageIfNeeded()` again — duplicating the user message.
**Fix**: Removed `userMessageEmitted = false` from `emitAIResponse()`. The flag is now only reset in `input_audio_buffer.speech_started`, which marks the true start of a new user turn.
**File**: `RealtimeConnection.swift` line ~426

### Info.plist Build Conflict (fixed 2026-02-09)
**Problem**: "Multiple commands produce Info.plist" when building for iOS, caused by `PBXFileSystemSynchronizedRootGroup` copying Info.plist as a resource while `GENERATE_INFOPLIST_FILE = YES` also generates it.
**Fix**: Added `PBXFileSystemSynchronizedBuildFileExceptionSet` excluding `Info.plist` from auto-sync membership.

### Weak Delegate Deallocation (fixed in prior session)
**Problem**: `ConversationBridge` assigned to `voiceEngine.delegate` (weak) was immediately deallocated.
**Fix**: Added `@State private var delegateBridge: ConversationBridge?` to hold strong reference.

## Outstanding Issues / TODO

### iOS UI
- [ ] `NavigationSplitView` on iPhone shows sidebar-first; workaround in place (iOS-specific "Start New Conversation" button at top of list) but not ideal
- [ ] macOS detail-view placeholder ("Welcome to Astute") is not visible on iPhone — by design, but may want a dedicated iPhone empty state

### Not Yet Tested
- [ ] iOS Simulator builds
- [ ] visionOS builds (project has `xros` in `SUPPORTED_PLATFORMS` but hasn't been tested)

### Package Versioning
- [ ] AstuteVoiceEngine is tagged `0.1.0` on GitHub but significant changes have been made since (transport protocol, enum state, configurable endpoints) — tag a new version
- [ ] AstuteMemory needs initial GitHub push and versioning

### Future Work
- [ ] Terra Tales (planned second consumer of AstuteVoiceEngine) has not been started yet
- [ ] Wake word detection via sherpa-onnx — see [docs/sherpa-onnx-research.md](docs/sherpa-onnx-research.md) for full research and proposed architecture
- [ ] AstuteMemory: consider caching summaries to avoid regenerating, add user preference extraction, conversation topic tagging

## Session History

> Full session notes archived in [docs/session-history.md](docs/session-history.md).

**Sessions 1-4**: Built Astute from scratch, extracted AstuteVoiceEngine package, added iOS support, removed Porcupine wake word detection.

**Session 5** (2026-02-10): Removed UI library from package. Refactored RealtimeConnection — os.log, guard/throw, MessageTracker, dedicated handler methods, reconnection improvements. Added 8 unit tests.

**Session 6** (2026-02-10): Extracted WebRTC behind `TransportProvider` protocol. Replaced 5 booleans with `ConnectionState`/`ConversationPhase` enums. Made endpoint/ICE/reconnect configurable. Added `MockTransport` and 35 RealtimeConnection tests. Total: 49 tests, 0 failures.

**Session 7** (2026-02-10): Created AstuteMemory Swift Package — conversation summarization, AI title generation, cross-session context injection via ContextBuilder. Integrated into Astute app: context injected before each voice connection, summary/title generated on conversation end, conversation search and summary preview in sidebar. Reorganized project documentation (CLAUDE.md, README, docs/).
