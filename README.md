# Astute

A voice conversation app for macOS and iOS powered by OpenAI's Realtime API. Tap to talk, and have natural voice conversations with AI — with real-time transcription, streaming responses, and full conversation history.

## Features

- **Voice conversations** — Tap the mic button to start talking. OpenAI's server-side voice activity detection handles turn-taking automatically.
- **Text input** — Type messages alongside voice. Text messages auto-connect if a session isn't active yet.
- **Real-time transcription** — See your speech transcribed live as you speak, with corrections applied when the final transcription arrives.
- **Streaming AI responses** — Watch the AI's response appear token by token, then hear it spoken back.
- **Conversation history** — All conversations are persisted locally via SwiftData with full message history.
- **Multiple AI voices** — Choose from six OpenAI voices: Alloy, Echo, Fable, Onyx, Nova, and Shimmer.
- **Secure API key storage** — Your OpenAI key is stored in the system Keychain, never in UserDefaults or plain text.
- **Cross-platform** — Runs natively on macOS and iOS from a single codebase.

## Requirements

- macOS 13+ or iOS 16+
- Xcode 16+
- An [OpenAI API key](https://platform.openai.com/api-keys) with access to the Realtime API
- The [AstuteVoiceEngine](https://github.com/dlarmitage/AstuteVoiceEngine) Swift package (referenced as a local package)

## Getting Started

### 1. Clone both repositories

```bash
# Clone the app
git clone https://github.com/dlarmitage/Astute.git

# Clone the voice engine package alongside it
git clone https://github.com/dlarmitage/AstuteVoiceEngine.git
```

The Xcode project expects `AstuteVoiceEngine` at `../../AstuteVoiceEngine` relative to the `.xcodeproj`. The directory layout should be:

```
parent-directory/
├── AstuteVoiceEngine/     ← Swift package
└── astute/
    └── Astute/            ← Xcode project
```

### 2. Open and build

Open `Astute.xcodeproj` in Xcode 16+. The local package reference should resolve automatically.

```bash
# Or build from the command line — macOS
xcodebuild -scheme Astute -destination 'platform=macOS' -skipPackagePluginValidation build

# iOS
xcodebuild -scheme Astute -destination 'generic/platform=iOS' -skipPackagePluginValidation build
```

### 3. Configure your API key

On first launch, the Settings sheet opens automatically. Enter your OpenAI API key — it's saved to the system Keychain and persists across app launches.

## Architecture

Astute is intentionally a thin UI and data layer (~935 lines of Swift). All voice, WebRTC, and OpenAI Realtime API logic lives in the [AstuteVoiceEngine](https://github.com/dlarmitage/AstuteVoiceEngine) package.

```
Astute/
├── AstuteApp.swift           App entry point, SwiftData container setup
├── ContentView.swift         Navigation split view, conversation list, sidebar
├── ConversationView.swift    Chat UI, voice controls, delegate bridge to SwiftData
├── SettingsView.swift        API key input, voice picker, connection status
├── Conversation.swift        SwiftData models (Conversation, ConversationMessage)
└── KeychainHelper.swift      Secure API key storage via Security framework
```

### How it works

1. **ContentView** manages the conversation list (SwiftData `@Query`) and sidebar navigation.
2. **ConversationView** creates a `VoiceEngine` instance from the package, wires up a `ConversationBridge` delegate to persist messages to SwiftData, and renders the chat UI.
3. When the user taps the mic button, the app requests microphone permission, then calls `voiceEngine.start()` which establishes a WebRTC connection to OpenAI's Realtime API.
4. Server-side VAD detects when the user starts and stops speaking. Transcription arrives incrementally via Whisper, and the AI streams its response back over the data channel.
5. The `ConversationBridge` delegate receives completed messages and persists them to SwiftData. It also updates in-progress transcriptions as Whisper refines them.

### Data model

```swift
Conversation
├── id: UUID
├── timestamp: Date
├── title: String              // Auto-populated from first user message
└── messages: [ConversationMessage]   // Cascade delete

ConversationMessage
├── id: UUID
├── role: String               // "user", "assistant", or "system"
├── content: String
├── timestamp: Date
└── audioData: Data?           // Reserved for future use
```

### Platform differences

| Feature | macOS | iOS |
|---------|-------|-----|
| Navigation | Split view with sidebar | List-first with inline actions |
| Mic permission | `AVCaptureDevice` | `AVAudioSession` |
| Window size | Default 1000x700 | System-managed |
| Settings access | Sidebar footer + toolbar | Inline list button + toolbar |

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [AstuteVoiceEngine](https://github.com/dlarmitage/AstuteVoiceEngine) | Local reference | Voice engine, WebRTC, OpenAI Realtime API |

AstuteVoiceEngine itself depends on [`stasel/WebRTC`](https://github.com/nicklama/WebRTC) v140.0.0.

## License

This project is proprietary. All rights reserved.
