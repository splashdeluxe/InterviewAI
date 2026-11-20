import Foundation

/// AI Hub transforms: a finished meeting turned into something
/// else — a brief summary, a thank-you email, study questions —
/// by the deep model on this Mac. The app shows them in a Create
/// section on the meeting page; this file carries everything that
/// can be tested without the app: the result and favorite models
/// and their store JSON, the built-in transform definitions, the
/// prompt fence every transform runs under, and the rule that
/// picks which transcript a transform reads. The app only runs
/// the model and stores the result.
public enum TransformSource: String, Codable, Sendable {
    case cleaned
    case original
    /// The meeting's summary: the translate and tone-rewrite
    /// transforms read it instead of a transcript.
    case summary

    /// The name the meeting page shows for the text a transform
    /// read, so the user can tell a result written from the Clean
    /// Transcript from one written from the original.
    public var label: String {
        switch self {
        case .cleaned: return "Clean Transcript"
        case .original: return "Original transcript"
        case .summary: return "Summary"
        }
    }
}

/// One transform's output, saved on the meeting it came from.
/// Running a transform again adds a new result; a result never
/// overwrites the meeting's summary, its follow-up, or an older
/// result.
public struct TransformResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// The transform's name as shown when it ran, for example
    /// "Brief Summary" or a favorite's name.
    public var name: String
    /// The instruction the transform ran with: a built-in's
    /// instruction, or the user's own words for a custom prompt.
    public var prompt: String
    public var text: String
    /// Which transcript the result was written from.
    public var source: TransformSource
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, prompt: String, text: String,
                source: TransformSource, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }

    /// Meetings store their transform results as one JSON string.
    public static func encode(_ results: [TransformResult]) -> String {
        guard let data = try? JSONEncoder().encode(results) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(_ json: String) -> [TransformResult] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TransformResult].self, from: data) else { return [] }
        return decoded
    }
}

/// A custom prompt the user saved to run again on any meeting.
/// Favorites are stored once, outside any single meeting, the way
/// custom modes are.
public struct TransformFavorite: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String

    public init(id: String = UUID().uuidString, name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }

    /// The favorites list is stored as one JSON string.
    public static func encode(_ favorites: [TransformFavorite]) -> String {
        guard let data = try? JSONEncoder().encode(favorites) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(_ json: String) -> [TransformFavorite] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TransformFavorite].self, from: data) else { return [] }
        return decoded
    }
}

/// One transform the user can pick: a name for the list and the
/// instruction the model runs. A favorite becomes a definition
/// whose instruction is the favorite's prompt.
public struct TransformDefinition: Equatable, Sendable {
    public var id: String
    public var name: String
    public var instruction: String

    public init(id: String, name: String, instruction: String) {
        self.id = id
        self.name = name
        self.instruction = instruction
    }
}

/// The transforms built into the app. Translate and tone rewrite
/// are made on demand because their instruction carries the
/// language or tone the user picked.
public enum BuiltInTransforms {
    public static let briefSummary = TransformDefinition(
        id: "briefSummary",
        name: "Brief Summary",
        instruction: "Write a brief summary of the text: at most 5 short lines, the essence only. No headings, no extra detail."
    )

    public static let detailedSummary = TransformDefinition(
        id: "detailedSummary",
        name: "Detailed Summary",
        instruction: "Write detailed notes from the text: what was discussed, the decisions made, and the open points. Use headings for decisions and open points when there are any."
    )

    public static let thankYouEmail = TransformDefinition(
        id: "thankYouEmail",
        name: "Thank-You Email",
        instruction: "Write a thank-you email to the other people in this meeting: warm and short, ready to send. Address it to the attendees named above when they are given, and thank them for the conversation and their time. Use no placeholders like [Name]; when no names are given, write the email without a name line."
    )

    public static let followUpEmail = TransformDefinition(
        id: "followUpEmail",
        name: "Follow-Up Email",
        instruction: "Write a follow-up email from the text: the agreed actions and the next steps, each with who owns it when the text says so. Include only actions the transcript supports; when no actions were agreed, say that plainly instead of inventing some."
    )

    public static let studyQuestions = TransformDefinition(
        id: "studyQuestions",
        name: "Study Questions",
        instruction: "Write questions that test understanding of this meeting, covering the main points in the order they came up. Questions only, no answers, numbered."
    )

    /// The fixed transforms, in the order the Create section
    /// lists them.
    public static let all: [TransformDefinition] = [briefSummary, detailedSummary, thankYouEmail, followUpEmail, studyQuestions]

    public static func translate(language: String) -> TransformDefinition {
        TransformDefinition(
            id: "translate",
            name: "Translate Summary",
            instruction: "Translate the text into \(language). Keep names, numbers, and dates unchanged, and keep the shape of the text: headings stay headings, lists stay lists."
        )
    }

    public static let tones = ["Professional", "Casual", "Confident"]

    public static func toneRewrite(tone: String) -> TransformDefinition {
        TransformDefinition(
            id: "tone",
            name: "Rewrite — \(tone)",
            instruction: "Rewrite the text in a \(tone) tone. Keep every fact, name, and number exactly as it is; change only the wording and the tone."
        )
    }
}

/// The prompt every transform runs under. The system line is the
/// fence, in the same spirit as the summary prompt: work only
/// from the text given, invent nothing, and when the text does
/// not hold what the task needs, say so in the result instead of
/// guessing.
public enum TransformPrompt {
    public static let system = """
        You carry out a writing task on text from a meeting: clear, complete, factual. \
        Work only from the text given to you. Never invent names, numbers, decisions, or roles that are not in it. \
        If the text does not contain what the task needs, say so plainly in the result instead of guessing. \
        Reply with the result only: no introduction, no commentary about the task.
        """

    /// The user message: the meeting's title and attendees when
    /// there are any, the transform's instruction, then the text
    /// to work on, labelled so the result can say where it came
    /// from.
    public static func userMessage(definition: TransformDefinition, inputLabel: String, inputText: String, title: String, attendees: [String]) -> String {
        var parts: [String] = []
        if !title.isEmpty {
            parts.append("Meeting: \(title)")
        }
        if !attendees.isEmpty {
            parts.append("Attendees: \(attendees.joined(separator: ", "))")
        }
        parts.append(definition.instruction)
        parts.append("Text (\(inputLabel)):\n\(inputText)")
        return parts.joined(separator: "\n\n")
    }
}

/// Which transcript a transform reads. The Clean Transcript wins
/// when the meeting has one; otherwise the original. A meeting
/// with neither has nothing to transform.
public enum TransformSourcePicker {
    public static func pick(cleaned: [TranscriptSegment], original: [TranscriptSegment]) -> (segments: [TranscriptSegment], source: TransformSource)? {
        if !cleaned.isEmpty { return (cleaned, .cleaned) }
        if !original.isEmpty { return (original, .original) }
        return nil
    }
}
