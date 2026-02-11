//
//  Conversation.swift
//  Astute
//
//  Created by David Armitage on 2/5/26.
//

import Foundation
import SwiftData
import AstuteMemory

@Model
final class Conversation {
    var id: UUID
    var timestamp: Date
    var title: String
    var summary: String?
    var isTitleGenerated: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ConversationMessage.conversation)
    var messages: [ConversationMessage]

    init(timestamp: Date = Date(), title: String = "New Conversation") {
        self.id = UUID()
        self.timestamp = timestamp
        self.title = title
        self.summary = nil
        self.isTitleGenerated = false
        self.messages = []
    }
}

extension Conversation: ConversationSnapshot {}

@Model
final class ConversationMessage {
    var id: UUID
    var role: String // Store as String for compatibility with SwiftData model macros
    var content: String
    var timestamp: Date
    var audioData: Data?
    var conversation: Conversation?

    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }

    init(role: MessageRole, content: String, timestamp: Date = Date(), audioData: Data? = nil) {
        self.id = UUID()
        self.role = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.audioData = audioData
    }

    var roleType: MessageRole {
        MessageRole(rawValue: role) ?? .system
    }
}

extension ConversationMessage: MessageSnapshot {}
