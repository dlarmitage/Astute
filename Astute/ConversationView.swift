//
//  ConversationView.swift
//  Astute
//
//  Created by David Armitage on 2/5/26.
//

import SwiftUI
import SwiftData
import AstuteVoiceEngine
import AstuteMemory

struct ConversationView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var voiceEngine: VoiceEngine
    @AppStorage("ai_voice") private var selectedVoice: String = "random"
    @State private var isRecording = false
    @State private var showSettings = false
    @State private var messageText = ""
    @State private var isSendingText = false
    /// Strong reference to keep the delegate alive (VoiceEngine holds it weakly).
    @State private var delegateBridge: ConversationBridge?

    @Bindable var conversation: Conversation
    private let apiKey: String

    private static let concreteVoices = ["alloy", "ash", "ballad", "cedar", "coral", "echo", "marin", "sage", "shimmer", "verse"]

    init(conversation: Conversation, apiKey: String) {
        self.conversation = conversation
        self.apiKey = apiKey
        let voicePref = UserDefaults.standard.string(forKey: "ai_voice") ?? "random"
        let voice = voicePref == "random"
            ? Self.concreteVoices.randomElement()!
            : voicePref
        let config = VoiceEngineConfiguration(
            apiKey: apiKey,
            voice: voice,
            greeting: .init(muteMicDuringGreeting: true)
        )
        _voiceEngine = StateObject(wrappedValue: VoiceEngine(configuration: config))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(conversation.messages, id: \.id) { message in
                            ChatBubble(role: message.roleType, content: message.content, timestamp: message.timestamp)
                        }

                        // Live transcription
                        if !voiceEngine.currentTranscription.isEmpty {
                            ChatBubble(role: .user, content: voiceEngine.currentTranscription)
                                .opacity(0.6)
                        }

                        // Live AI response
                        if !voiceEngine.currentAIResponse.isEmpty {
                            ChatBubble(role: .assistant, content: voiceEngine.currentAIResponse)
                                .opacity(0.6)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .onChange(of: voiceEngine.contentUpdateTrigger) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Controls area
            VStack(spacing: 12) {
                // Status indicator
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if voiceEngine.isConnected {
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                // Error message
                if let error = voiceEngine.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // Text input + mic button row
                HStack(spacing: 12) {
                    // Text field with inline send button
                    HStack(spacing: 8) {
                        TextField("Type a message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...5)
                            .onSubmit {
                                sendTextMessage()
                            }

                        // Send button — only visible when there is text
                        if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: sendTextMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSendingText)
                        }
                    }
                    .padding(8)
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #else
                    .background(Color(.systemGray6))
                    #endif
                    .cornerRadius(20)

                    // Mic toggle button (compact circle)
                    Button(action: toggleRecording) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(isRecording ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    .help(isRecording ? "Stop voice conversation" : "Start voice conversation")
                }
            }
            .padding()
        }
        .navigationTitle(conversation.title)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings.toggle() }) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            // Wire up per-message persistence via delegate.
            // Must store a strong reference — VoiceEngine.delegate is weak.
            let bridge = ConversationBridge(
                conversation: conversation,
                modelContext: modelContext
            )
            delegateBridge = bridge
            voiceEngine.delegate = bridge
        }
        .onDisappear {
            voiceEngine.stop()
            // Generate summary and title in background after leaving
            let conv = conversation
            let key = apiKey
            let context = modelContext
            Task.detached { @MainActor in
                await generateMemory(for: conv, apiKey: key, modelContext: context)
            }
        }
    }

    private var statusColor: Color {
        if voiceEngine.isAIResponding {
            return .orange
        } else if voiceEngine.isUserSpeaking {
            return .purple
        } else if isRecording {
            return .green
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if voiceEngine.isAIResponding {
            return "AI is responding..."
        } else if voiceEngine.isUserSpeaking {
            return "Hearing you..."
        } else if isRecording {
            return "Listening..."
        } else {
            return "Ready"
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            let granted = await voiceEngine.requestMicrophonePermission()

            guard granted else {
                return
            }

            do {
                // Set context BEFORE connecting so the initial session.update
                // includes conversation memory (avoids race with sendSessionUpdate)
                injectConversationContext()
                try await voiceEngine.start()
                isRecording = true
            } catch {
                // errorMessage is published by the engine
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        voiceEngine.stop()
    }

    private func sendTextMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messageText = ""  // Clear immediately for responsiveness
        isSendingText = true

        if voiceEngine.isConnected {
            // Already connected — send directly via data channel
            voiceEngine.sendTextMessage(text)
            isSendingText = false
        } else {
            // Not connected — send (queues it + persists user bubble), then auto-connect
            voiceEngine.sendTextMessage(text)
            Task {
                do {
                    let granted = await voiceEngine.requestMicrophonePermission()
                    guard granted else {
                        isSendingText = false
                        return
                    }
                    injectConversationContext()
                    try await voiceEngine.start()
                    isRecording = true
                    isSendingText = false
                } catch {
                    isSendingText = false
                }
            }
        }
    }

    // MARK: - Memory

    private static let baseInstructions = """
        You are a helpful and friendly AI assistant. You respond naturally via voice \
        and text. Keep your responses concise but engaging.
        """

    private func injectConversationContext() {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.timestamp, order: .reverse)]
        )
        let allConversations = (try? modelContext.fetch(descriptor)) ?? []
        let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        let instructions = ContextBuilder.buildInstructions(
            baseInstructions: Self.baseInstructions,
            currentMessages: sortedMessages,
            pastConversations: allConversations.filter { $0.id != conversation.id }
        )

        voiceEngine.updateInstructions(instructions)
    }
}

// MARK: - Memory Generation (free function for Task.detached)

@MainActor
private func generateMemory(
    for conversation: Conversation,
    apiKey: String,
    modelContext: ModelContext
) async {
    let sortedMessages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

    if conversation.summary == nil && sortedMessages.count >= 2 {
        do {
            let summary = try await Summarizer.summarize(
                messages: sortedMessages,
                apiKey: apiKey
            )
            conversation.summary = summary
        } catch {
            print("[Astute] Summarization failed: \(error.localizedDescription)")
        }
    }

    if !conversation.isTitleGenerated && !sortedMessages.isEmpty {
        do {
            let title = try await TitleGenerator.generateTitle(
                messages: sortedMessages,
                apiKey: apiKey
            )
            conversation.title = title
            conversation.isTitleGenerated = true
        } catch {
            print("[Astute] Title generation failed: \(error.localizedDescription)")
        }
    }

    try? modelContext.save()
}

// MARK: - Delegate Bridge

/// Bridges VoiceEngineDelegate callbacks to SwiftData persistence.
@MainActor
private class ConversationBridge: VoiceEngineDelegate {
    let conversation: Conversation
    let modelContext: ModelContext

    /// Tracks the most recently emitted user message so its content can be
    /// updated when the final Whisper transcription arrives.
    /// Owned directly by the bridge — no Binding needed.
    private var lastUserMessage: ConversationMessage?

    init(conversation: Conversation, modelContext: ModelContext) {
        self.conversation = conversation
        self.modelContext = modelContext
    }

    func voiceEngine(_ engine: VoiceEngine, didCompleteMessage message: VoiceMessage) {
        switch message {
        case .user(let transcript):
            guard !transcript.isEmpty else { return }
            let userMessage = ConversationMessage(role: .user, content: transcript)
            userMessage.conversation = conversation
            conversation.messages.append(userMessage)
            modelContext.insert(userMessage)
            lastUserMessage = userMessage

            // Temporary title until AI generates one on conversation end
            if conversation.title == "New Conversation" && !conversation.isTitleGenerated && transcript != "…" {
                conversation.title = String(transcript.prefix(50))
            }

        case .ai(let response):
            guard !response.isEmpty else { return }
            let aiMessage = ConversationMessage(role: .assistant, content: response)
            aiMessage.conversation = conversation
            conversation.messages.append(aiMessage)
            modelContext.insert(aiMessage)
            // Note: do NOT clear lastUserMessage here — transcription.completed
            // can arrive after response.done, and the update callback needs the
            // reference to fix the "…" placeholder.
        }

        try? modelContext.save()
    }

    func voiceEngine(_ engine: VoiceEngine, didUpdateUserMessage transcript: String) {
        guard let msg = lastUserMessage, !transcript.isEmpty else { return }
        msg.content = transcript
        // Update temporary title if it was still placeholder
        if (conversation.title == "New Conversation" || conversation.title == "…")
            && !conversation.isTitleGenerated {
            conversation.title = String(transcript.prefix(50))
        }
        try? modelContext.save()
    }

    func voiceEngine(_ engine: VoiceEngine, didEncounterError error: VoiceEngineError) {
        print("[Astute] VoiceEngine error: \(error.localizedDescription)")
    }
}

// MARK: - Unified Chat Bubble

struct ChatBubble: View {
    let role: ConversationMessage.MessageRole
    let content: String
    var timestamp: Date? = nil

    var body: some View {
        HStack {
            if role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
                Text(content)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    .cornerRadius(16)

                if let timestamp {
                    Text(timestamp, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    private var backgroundColor: Color {
        switch role {
        case .user:
            return .blue
        case .assistant:
            #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color(.systemGray5)
            #endif
        case .system:
            #if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color(.systemGray6)
            #endif
        }
    }

    private var textColor: Color {
        switch role {
        case .user:
            return .white
        case .assistant, .system:
            return .primary
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Conversation.self, configurations: config)
    let conversation = Conversation(title: "Preview Conversation")

    conversation.messages = [
        ConversationMessage(role: .user, content: "Hello, how are you?"),
        ConversationMessage(role: .assistant, content: "I'm doing great! How can I help you today?"),
        ConversationMessage(role: .user, content: "Can you tell me about SwiftUI?"),
        ConversationMessage(role: .assistant, content: "SwiftUI is Apple's modern framework for building user interfaces across all Apple platforms.")
    ]

    return NavigationStack {
        ConversationView(conversation: conversation, apiKey: "demo-key")
    }
    .modelContainer(container)
}
