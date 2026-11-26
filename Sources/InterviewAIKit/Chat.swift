import Foundation

/// One message in an Ask chat: the user's question or the
/// assistant's answer, with the sources the answer drew on.
public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// "user" or "assistant".
    public var role: String
    public var text: String
    public var sources: [String]
    /// A note about how the answer was produced, e.g. that
    /// the live model answered because the deep one was away.
    public var note: String?

    public init(id: UUID = UUID(), role: String, text: String, sources: [String] = [], note: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.sources = sources
        self.note = note
    }

    public static func encode(_ messages: [ChatMessage]) -> String {
        let data = (try? JSONEncoder().encode(messages)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func decode(_ text: String) -> [ChatMessage] {
        guard let data = text.data(using: .utf8),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return [] }
        return messages
    }
}

/// How a chat turn is assembled: which of the earlier
/// messages ride along, and the prompt the model sees.
public enum ChatPrompt {
    public static let system = "You answer questions about the user's own meetings and files, in a conversation. Use only the material given and what was said earlier in this conversation, and say plainly when neither covers the question. Name the meeting or file each fact came from. Answer directly, in the language of the question."

    /// The recent turns that give a follow-up its meaning:
    /// the last few messages, oldest first, cut from the
    /// front when they grow past the character budget. The
    /// newest message always rides along.
    public static func window(_ messages: [ChatMessage], maxMessages: Int = 6, maxChars: Int = 3_000) -> [ChatMessage] {
        var kept: [ChatMessage] = []
        var chars = 0
        for message in messages.suffix(maxMessages).reversed() {
            chars += message.text.count
            if !kept.isEmpty, chars > maxChars { break }
            kept.append(message)
        }
        return kept.reversed()
    }

    /// The user message for one turn: the conversation so
    /// far, the freshly ranked material, and the question.
    public static func userMessage(history: [ChatMessage], material: String, question: String) -> String {
        var parts: [String] = []
        if !history.isEmpty {
            let lines = history.map { "\($0.role == "user" ? "User" : "Assistant"): \($0.text)" }
            parts.append("Conversation so far:\n" + lines.joined(separator: "\n"))
        }
        parts.append("Material:\n\(material)")
        parts.append("Question: \(question)")
        return parts.joined(separator: "\n\n")
    }
}
