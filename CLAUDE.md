# Astute - Project Handoff Document

> Last updated: 2026-02-10

## Overview

**Astute** is a macOS + iOS SwiftUI voice conversation app using OpenAI's Realtime API via WebRTC. Users start voice conversations via a button tap. The voice engine has been extracted into a reusable Swift Package (**AstuteVoiceEngine**) so it can be shared across multiple apps.

## Architecture

```
Astute (App)                          AstuteVoiceEngine (Swift Package)
├── ContentView.swift                 └── AstuteVoiceEngine (library)
├── ConversationView.swift                ├── VoiceEngine.swift          (public facade)
│   ├── VoiceEngine (from pkg)            ├── RealtimeConnection.swift    (session coordinator)
│   └── ConversationBridge (delegate)     ├── TransportProvider.swift     (transport protocol)
├── SettingsView.swift                    ├── WebRTCTransport.swift       (WebRTC implementation)
├── KeychainHelper.swift                  ├── MessageTracker.swift        (turn state machine)
├── Conversation.swift (SwiftData)        ├── VoiceEngineConfiguration.swift
└── AstuteApp.swift                       ├── VoiceEngineDelegate.swift
                                          ├── MicrophonePermissions.swift
                                          └── Types.swift (VoiceMessage, VoiceEngineError,
                                                           ConnectionState, ConversationPhase)
```

## Key Repositories

| Repo | Path | Remote |
|------|------|--------|
| Astute (app) | `/Users/darmitage/Library/Mobile Documents/com~apple~CloudDocs/xCode/astute/Astute` | `https://github.com/dlarmitage/astute` |
| AstuteVoiceEngine (package) | `/Users/darmitage/Library/Mobile Documents/com~apple~CloudDocs/xCode/AstuteVoiceEngine` | `https://github.com/dlarmitage/AstuteVoiceEngine` |

The app references the package via a **local** `XCLocalSwiftPackageReference` at `../../AstuteVoiceEngine`.

## Key Technical Details

### WebRTC + OpenAI Realtime API
- Uses `stasel/WebRTC` Swift package v140.0.0
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

### Cross-Platform (macOS + iOS)
- `MicrophonePermissions.swift`: Uses `AVCaptureDevice` on macOS, `AVAudioSession.recordPermission` on iOS

### Delegate Pattern
- `VoiceEngine.delegate` is **weak** — consuming app MUST hold a strong reference
- Astute uses `ConversationBridge` class implementing `VoiceEngineDelegate`, stored in `@State private var delegateBridge: ConversationBridge?`
- Bridge persists messages to SwiftData (`Conversation`, `ConversationMessage`)

### Xcode Project Specifics
- Uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ auto-sync from filesystem)
- `PBXFileSystemSynchronizedBuildFileExceptionSet` excludes `Info.plist` from auto-sync (prevents "multiple commands produce Info.plist" error)
- `XCSwiftPackageProductDependency` entries require `package` back-reference to the `XCLocalSwiftPackageReference`

### API Keys
- Stored in macOS/iOS Keychain via `KeychainHelper.swift`
- OpenAI key: service `com.astute.openai`, account `api_key` (`kSecClassGenericPassword`)
- Viewable in Keychain Access.app (NOT the new Passwords app)

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

### Uncommitted Changes
1. **AstuteVoiceEngine package** has uncommitted changes:
   - `RealtimeConnection.swift` — major rewrite: removed WebRTC dependency, accepts `TransportProvider` via DI, replaced 5 boolean `@Published` properties with `ConnectionState`/`ConversationPhase` enums, uses configurable endpoint/ICE/reconnect settings
   - `TransportProvider.swift` — new file: protocol abstracting transport layer + `TransportConnectionState` enum + `ConnectionConfiguration` struct
   - `WebRTCTransport.swift` — new file: extracted WebRTC implementation (only file importing WebRTC), implements `TransportProvider`
   - `Types.swift` — added `ConnectionState` and `ConversationPhase` public enums
   - `VoiceEngineConfiguration.swift` — added `realtimeEndpoint`, `iceServers: [IceServer]`, `maxReconnectAttempts`, `maxReconnectDelay` with backward-compatible defaults
   - `VoiceEngine.swift` — updated bindings to use `.map` on enum publishers instead of direct boolean forwarding
   - `MessageTracker.swift` — new file (prior session): extracted per-turn message state machine
   - `Package.swift` — removed AstuteWakeWord, CPorcupine, PvPorcupine targets; removed AstuteVoiceEngineUI library
   - Deleted `Sources/AstuteVoiceEngineUI/` directory
   - Tests: added `MockTransport.swift`, `RealtimeConnectionTests.swift` (35 tests), updated config tests for new properties. Total: 49 tests, 0 failures

2. **Astute app** has many uncommitted changes across the entire project (ContentView, ConversationView, SettingsView, KeychainHelper, pbxproj)

### iOS UI
- `NavigationSplitView` on iPhone shows sidebar-first; added iOS-specific section with "Start New Conversation" button at top of list
- The macOS detail-view placeholder with "Welcome to Astute" is not visible on iPhone (by design — iPhone uses the list section instead)

### Not Yet Tested
- iOS Simulator builds
- visionOS builds (project has xros in SUPPORTED_PLATFORMS but hasn't been tested)
### Future Considerations
- The package is tagged `0.1.0` on GitHub but significant changes have been made since (iOS support, wake word removal, duplicate fix, UI library removal)
- Consider tagging a new version after committing all changes
- The Astute app repo has never had a proper commit beyond "Initial Commit" — needs a comprehensive commit
- Each consuming app builds its own UI on top of the engine (AstuteVoiceEngineUI was removed — decision: apps own their UI)
- Terra Tales (the planned second consumer of this package) has not been started yet

## Build Verification Commands

```bash
# Package — macOS
cd "/Users/darmitage/Library/Mobile Documents/com~apple~CloudDocs/xCode/AstuteVoiceEngine"
swift build
swift test

# App — macOS
cd "/Users/darmitage/Library/Mobile Documents/com~apple~CloudDocs/xCode/astute/Astute"
xcodebuild -scheme Astute -destination 'platform=macOS' -skipPackagePluginValidation build

# App — iOS
xcodebuild -scheme Astute -destination 'generic/platform=iOS' -skipPackagePluginValidation build
```

## Session History (Condensed)

1. **Session 1** (prior): Built Astute from scratch — OpenAI Realtime API, WebRTC, Porcupine wake word, greeting feature, VAD tuning
2. **Session 2** (prior): Extracted code into AstuteVoiceEngine Swift Package, pushed to GitHub, refactored Astute to consume it, fixed weak delegate bug, renamed repo
3. **Session 3** (2026-02-09):
   - Made package cross-platform (iOS + macOS): MicrophonePermissions, WakeWordEngine, WakeWordConfiguration
   - Bundled `PvPorcupine.xcframework` for iOS
   - Fixed Info.plist build conflict, macOS dylib linking on iOS, duplicate user messages
   - Added iOS-specific UI (list section with status and new conversation button)
   - Confirmed voice conversations work on physical iPhone
4. **Session 4** (2026-02-09):
   - Removed Porcupine wake word detection entirely (cost/complexity decision)
   - Removed AstuteWakeWord, CPorcupine, PvPorcupine from package
   - Removed .ppn files, libpv_porcupine.dylib, Frameworks directory from app
   - Cleaned up ContentView, ConversationView, SettingsView, KeychainHelper, project.pbxproj
   - App now uses button-only activation for voice conversations
5. **Session 5** (2026-02-10):
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
6. **Session 6** (2026-02-10):
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
