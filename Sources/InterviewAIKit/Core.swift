import Foundation

/// One transcript line from one channel. "them" is system audio (the other
/// side of the call), "me" is the microphone.
public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var channel: String
    public var text: String
    public var at: Date
    public var isFinal: Bool
    /// The line translated into the reader's language, when translation
    /// is on. The original stays in `text`; nothing is overwritten.
    public var translatedText: String?
    /// "Speaker 1", "Speaker 2", ... from diarization of the other
    /// side. Nil until speakers are identified.
    public var speakerLabel: String?
    /// Seconds from the session start to the start of this line's audio,
    /// and how many seconds of audio the line covers. Diarization maps
    /// speakers onto lines through these two.
    public var startOffset: Double?
    public var duration: Double?

    public init(id: UUID = UUID(), channel: String, text: String, at: Date = Date(), isFinal: Bool = false,
                translatedText: String? = nil, speakerLabel: String? = nil,
                startOffset: Double? = nil, duration: Double? = nil) {
        self.id = id
        self.channel = channel
        self.text = text
        self.at = at
        self.isFinal = isFinal
        self.translatedText = translatedText
        self.speakerLabel = speakerLabel
        self.startOffset = startOffset
        self.duration = duration
    }

    public var speakerName: String {
        if let speakerLabel { return speakerLabel }
        return channel == "me" ? "Me" : "Them"
    }

    /// What the reader sees as the line: the translation when there is
    /// one, otherwise the original.
    public var displayText: String { translatedText ?? text }

    public static func encode(_ segments: [TranscriptSegment]) -> String {
        guard let data = try? JSONEncoder().encode(segments),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    public static func decode(_ text: String) -> [TranscriptSegment] {
        guard let data = text.data(using: .utf8),
              let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) else { return [] }
        return segments
    }

    /// Plain transcript for prompts and export: one "Them: ..." line each.
    public static func plainText(_ segments: [TranscriptSegment]) -> String {
        segments.filter(\.isFinal).map { "\($0.speakerName): \($0.text)" }.joined(separator: "\n")
    }
}

/// The seven actions on the overlay action row. Each one is an instruction
/// added to the user's question when the model writes the answer.
public enum AnswerAction: String, CaseIterable, Sendable {
    case whatToSay, clarify, recap, followUp, answer, codeHint, brainstorm

    public var title: String {
        switch self {
        case .whatToSay: "What Should I Say"
        case .clarify: "Clarify"
        case .recap: "Recap"
        case .followUp: "Follow-Up"
        case .answer: "Answer"
        case .codeHint: "Code Hint"
        case .brainstorm: "Brainstorm"
        }
    }

    public var symbol: String {
        switch self {
        case .whatToSay: "text.bubble"
        case .clarify: "questionmark.bubble"
        case .recap: "arrow.counterclockwise"
        case .followUp: "arrow.turn.up.right"
        case .answer: "bolt"
        case .codeHint: "chevron.left.forwardslash.chevron.right"
        case .brainstorm: "lightbulb"
        }
    }

    /// What the model is told to do, in plain words.
    public var instruction: String {
        switch self {
        case .whatToSay: "Tell me exactly what to say next, word for word, in first person, ready to speak out loud."
        case .clarify: "Give me one short clarifying question to ask, plus one sentence on why it helps."
        case .recap: "Recap what has been said so far: the key points, any numbers, and anything I agreed to."
        case .followUp: "Give me two or three good follow-up questions I can ask now, each one line."
        case .answer: "Answer the last question from the other side directly and completely, in first person, ready to speak."
        case .codeHint: "Give me a hint for the coding problem on screen or in the conversation: the approach and the key step, not the full solution."
        case .brainstorm: "Give me two or three approaches with their trade-offs, starting simple and ending with the strongest one."
        }
    }

    /// The Command-number shortcut, Command-1 to Command-7 in row order.
    public static func action(forNumber number: Int) -> AnswerAction? {
        let all = Self.allCases
        guard number >= 1, number <= all.count else { return nil }
        return all[number - 1]
    }
}

/// Whether a settled line from the other side deserves an automatic
/// answer. Back-channels ("Yeah.", "Okay.") and fragments do not: the
/// old behaviour answered every line, which wasted the model on noise
/// and could keep it generating for hours in an empty room. A line
/// earns an answer when it asks something, or when it is long enough
/// to be a real prompt. Deliberately predictable, no learning.
public enum AutoAnswerGate {
    private static let questionStarters = [
        "what", "how", "why", "when", "where", "who", "which",
        "can you", "could you", "would you", "do you", "did you",
        "have you", "are you", "tell me", "describe", "walk me",
        "explain", "give me an example",
    ]

    public static func shouldAnswer(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split { !$0.isLetter && !$0.isNumber }
        guard words.count >= 3 else { return false }
        if trimmed.hasSuffix("?") { return true }
        let lowered = trimmed.lowercased()
        if questionStarters.contains(where: { lowered.contains($0) }) { return true }
        return words.count >= 10
    }
}
