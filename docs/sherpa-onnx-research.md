# sherpa-onnx — Wake Word & On-Device Speech Research

> Researched: 2026-02-10

## Summary

sherpa-onnx is a comprehensive on-device speech toolkit from the Next-gen Kaldi project. It was evaluated as a potential replacement for the removed Porcupine wake word detection. No implementation work has been done — this is research only.

**Repo**: https://github.com/k2-fsa/sherpa-onnx (10.3k stars, Apache 2.0, very active — releases every 1-2 weeks)

**What it is**: Runs 100% locally via ONNX Runtime, no network required.

## Capabilities (all on-device)

- **Keyword spotting / wake word** — open-vocabulary (define keywords in a text file, no retraining), ~3 MB models, English + Chinese
- **Speech-to-text** — streaming and non-streaming (Zipformer, WeNet, Dolphin, FunASR, etc.)
- **Text-to-speech** — Piper VITS, Matcha, Kokoro, Kitten, Pocket
- **Voice activity detection (VAD)**
- **Speaker identification / verification / diarization**
- **Speech enhancement, source separation, language identification**

## Wake Word Approach vs. Porcupine

- Open-vocabulary: change keywords at runtime via text file (vs. Porcupine's pre-trained .ppn files per keyword)
- No per-device licensing fees (Apache 2.0 vs. Porcupine's commercial license)
- Fundamentally a constrained tiny ASR decoder, not a dedicated wake-word neural network — likely higher false-positive/negative rates for specific wake words, but tunable via boosting scores and trigger thresholds
- Models: `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01` (English, 3.3 MB, trained on GigaSpeech 10k hrs)

## Integration Considerations

- **No SPM or CocoaPods** — must build from source via CMake (`build-ios.sh`), producing `sherpa-onnx.xcframework` + `ios-onnxruntime.xcframework`
- Swift API is a thin C bridging header wrapper, not a native Swift framework
- Swift examples exist (`swift-api-examples/keyword-spotting-from-file.swift`) but only process files — no real-time iOS keyword spotting demo
- iOS SwiftUI demo apps exist for STT, TTS, language ID — but not keyword spotting

## Architectural Analysis & Design Decisions

### Why a `WakeWordProvider` protocol

The same dependency-injection pattern that made `TransportProvider` successful applies here. `VoiceEngine` shouldn't know about sherpa-onnx, C bridging headers, or ONNX Runtime — it should accept a protocol with `start(keywords:)`, `stop()`, and an `onKeywordDetected` callback. This keeps the engine testable (mock wake word provider), lets consuming apps opt in or out, and makes it possible to swap implementations later.

### Why the xcframeworks should NOT live in AstuteVoiceEngine

The engine is currently a clean Swift package with a single binary dependency (WebRTC). Adding two more xcframeworks (sherpa-onnx + onnxruntime) that require building from source via CMake would make the package fragile and hard for new consumers to adopt. Better options: (a) the consuming app bundles the frameworks and passes a `SherpaWakeWord` instance to the engine, or (b) a separate `AstuteSherpaIntegration` package wraps the C API and vends the provider.

### Accuracy trade-off

The open-vocabulary keyword spotter is a constrained ASR decoder — it's listening for any speech that matches a phonetic pattern, not a purpose-trained neural network for one specific phrase. For a wake word like "Hey Astute", this means: probably fine in quiet environments, likely more false positives in noisy/conversational settings than Porcupine was. The tunable boosting scores and trigger thresholds help, but real-world testing is essential before committing.

### The real-time mic gap

sherpa-onnx's Swift examples only process audio files. The engine already has real-time mic capture via `WebRTCTransport`, but that audio stream feeds directly into WebRTC's peer connection — it's not easily tapped. A wake word system needs its own audio pipeline (AVAudioEngine or AVAudioSession) that runs independently, before the WebRTC connection is established. This is a non-trivial integration point.

### Progressive adoption path

Start with keyword spotting, but the same framework supports local VAD (could replace or supplement server-side VAD), local STT (offline fallback when network is unavailable), and local TTS (for canned responses without API calls). Each could be a separate provider protocol, all backed by the same sherpa-onnx xcframeworks. This makes the initial xcframework integration cost pay dividends across multiple features.

## Proposed Architecture (not yet implemented)

- New `WakeWordProvider` protocol in AstuteVoiceEngine — `start(keywords:)`, `stop()`, `onKeywordDetected` callback
- `SherpaWakeWord` concrete implementation — only file importing sherpa C API, manages its own AVAudioEngine-based mic capture pipeline
- The xcframeworks live in the consuming app or a separate integration package, not inside AstuteVoiceEngine
- `VoiceEngine` accepts an optional `WakeWordProvider` — when set, starts listening on init, triggers `startWithGreeting()` on keyword detection
- Future providers using the same xcframeworks: `SherpaVAD`, `SherpaSTT`, `SherpaTTS`

## Next Step — Build Spike (recommended before any architecture work)

1. Clone sherpa-onnx, run `build-ios.sh`, measure resulting xcframework sizes
2. Run `keyword-spotting-from-file.swift` example against a test audio clip containing "Hey Astute"
3. Evaluate: false positive rate, false negative rate, latency, CPU usage on device
4. If the build process is fragile or accuracy is unacceptable, stop here — the architecture isn't worth building on a shaky foundation
5. If viable, proceed with `WakeWordProvider` protocol design and `SherpaWakeWord` implementation

## Key Risks

- Build-from-source via CMake may be fragile across Xcode/macOS versions
- xcframework binary size (ONNX Runtime alone may be significant)
- No existing real-time iOS keyword spotting example — must build mic-to-spotter pipeline from scratch
- Open-vocabulary accuracy for a specific wake phrase may not match purpose-trained alternatives
