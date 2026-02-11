//
//  ContentView.swift
//  Astute
//
//  Created by David Armitage on 2/5/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.timestamp, order: .reverse) private var conversations: [Conversation]
    @State private var apiKey: String = ""

    @State private var selectedConversation: Conversation?
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $selectedConversation) {
                    #if os(iOS)
                    // On iPhone, show quick actions in the list itself
                    Section {
                        if apiKey.isEmpty {
                            Button(action: { showSettings.toggle() }) {
                                Label("Configure API Key", systemImage: "key")
                                    .foregroundColor(.orange)
                            }
                        } else {
                            Button(action: startManualConversation) {
                                Label("Start New Conversation", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                    #endif

                    Section {
                        ForEach(conversations) { conversation in
                            NavigationLink(value: conversation) {
                                ConversationRow(conversation: conversation)
                            }
                        }
                        .onDelete(perform: deleteConversations)
                    }
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                #endif

                // Sidebar footer
                VStack(spacing: 8) {
                    Divider()

                    HStack {
                        Button(action: { showSettings.toggle() }) {
                            Label("Settings", systemImage: "gear")
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        if apiKey.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                #if os(macOS)
                                .help("API key not configured")
                                #endif
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                #endif
                ToolbarItem {
                    Button(action: addConversation) {
                        Label("New Conversation", systemImage: "plus")
                    }
                    .disabled(apiKey.isEmpty)
                }
                ToolbarItem {
                    Button(action: { showDeleteAllConfirmation = true }) {
                        Label("Delete All", systemImage: "trash")
                    }
                    .disabled(conversations.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete All Conversations?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    deleteAllConversations()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(conversations.count) conversations. This cannot be undone.")
            }
            .navigationTitle("Astute")
        } detail: {
            if let conversation = selectedConversation {
                if !apiKey.isEmpty {
                    ConversationView(conversation: conversation, apiKey: apiKey)
                } else {
                    apiKeyRequiredView
                }
            } else {
                placeholderView
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            apiKey = KeychainHelper.load() ?? ""
            // Show settings on first launch if no API key
            if apiKey.isEmpty && conversations.isEmpty {
                showSettings = true
            }
        }
        .onChange(of: showSettings) { _, isShowing in
            if !isShowing {
                // Reload key when settings sheet dismisses
                apiKey = KeychainHelper.load() ?? ""
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            Text("Welcome to Astute")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Start a new conversation to chat with AI using your voice")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if apiKey.isEmpty {
                Button(action: { showSettings.toggle() }) {
                    Label("Configure API Key", systemImage: "key")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: startManualConversation) {
                    Label("New Conversation", systemImage: "plus.circle")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var apiKeyRequiredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.slash")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("API Key Required")
                .font(.title)
                .fontWeight(.bold)

            Text("Please configure your OpenAI API key in settings to use this conversation")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            Button(action: { showSettings.toggle() }) {
                Label("Open Settings", systemImage: "gear")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Creates a conversation and enters it.
    private func startManualConversation() {
        withAnimation {
            let newConversation = Conversation()
            modelContext.insert(newConversation)
            selectedConversation = newConversation
        }
    }

    private func addConversation() {
        withAnimation {
            selectedConversation = nil
        }
    }

    private func deleteConversations(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(conversations[index])
            }
        }
    }

    private func deleteAllConversations() {
        withAnimation {
            selectedConversation = nil
            for conversation in conversations {
                modelContext.delete(conversation)
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(conversation.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !conversation.messages.isEmpty {
                    Text("\(conversation.messages.count) messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Conversation.self, inMemory: true)
}
