//
//  SettingsView.swift
//  Astute
//
//  Created by David Armitage on 2/5/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @AppStorage("ai_voice") private var selectedVoice: String = "random"
    @Environment(\.dismiss) private var dismiss

    let availableVoices = ["random", "alloy", "ash", "ballad", "cedar", "coral", "echo", "marin", "sage", "shimmer", "verse"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("OpenAI API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            if newValue.isEmpty {
                                _ = KeychainHelper.delete()
                            } else {
                                _ = KeychainHelper.save(newValue)
                            }
                        }

                    if !apiKey.isEmpty && !apiKey.hasPrefix("sk-") {
                        Text("API key should start with \"sk-\"")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Text("Your key is stored securely in the system Keychain")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                } header: {
                    Text("OpenAI Configuration")
                }

                Section {
                    Picker("Voice", selection: $selectedVoice) {
                        ForEach(availableVoices, id: \.self) { voice in
                            if voice == "random" {
                                Text("Random").tag(voice)
                            } else {
                                Text(voice.capitalized).tag(voice)
                            }
                        }
                    }

                    if selectedVoice == "random" {
                        Text("A different voice will be chosen for each conversation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Voice Settings")
                }

                Section {
                    HStack {
                        Text("OpenAI")
                        Spacer()
                        if apiKey.isEmpty {
                            Label("Not Configured", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        } else {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Text("Connection")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            apiKey = KeychainHelper.load() ?? ""
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}

#Preview {
    SettingsView()
}
