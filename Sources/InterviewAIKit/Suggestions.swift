import Foundation

/// One automatic suggestion: a proactive coaching tip offered while a
/// session runs. The text is one line the user can say out loud word
/// for word, or one thing to notice; the why is one short line on why
/// it helps at that moment. Suggestions are drafted as candidates and
/// pass a strict filter before one is shown, so most are thrown away.
public struct Suggestion: Equatable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case ask
        case followUp
        case missedDetail
        case framing

        /// The short label shown with the tip.
        public var tag: String {
            switch self {
            case .ask: "Ask"
            case .followUp: "Follow up"
            case .missedDetail: "Missed detail"
            case .framing: "Framing"
            }
        }

        /// The kind as the drafting model names it, tolerant of the
        /// spellings a small model reaches for.
        public init?(modelName: String) {
            switch modelName.lowercased().trimmingCharacters(in: .whitespaces) {
            case "ask", "question": self = .ask
            case "follow-up", "follow up", "followup", "follow": self = .followUp
            case "missed", "missed detail", "detail", "missed-detail": self = .missedDetail
            case "framing", "reframe", "phrasing": self = .framing
            default: return nil
            }
        }
    }

    public var kind: Kind
    public var text: String
    public var why: String

    public init(kind: Kind, text: String, why: String) {
        self.kind = kind
        self.text = text
        self.why = why
    }

    /// Meetings store their session's suggestions as one JSON string.
    public static func encode(_ suggestions: [Suggestion]) -> String {
        guard let data = try? JSONEncoder().encode(suggestions) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(_ json: String) -> [Suggestion] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Suggestion].self, from: data) else { return [] }
        return decoded
    }
}

/// How often the suggestion engine may offer a tip. The cadence is a
/// minimum gap between evaluations, not a promise: a cycle that finds
/// nothing worth saying shows nothing.
public enum SuggestionFrequency: String, CaseIterable, Sendable {
    case off
    case selective
    case balanced
    case frequent

    public var label: String {
        switch self {
        case .off: "Off"
        case .selective: "Selective"
        case .balanced: "Balanced"
        case .frequent: "Frequent"
        }
    }

    /// Seconds between two evaluations of the conversation.
    public var cadence: TimeInterval {
        switch self {
        case .off: .infinity
        case .selective: 240
        case .balanced: 150
        case .frequent: 90
        }
    }
}

/// The suggestion engine's pure decisions: when a cycle may run, how
/// model output becomes tips, and how repeats are caught. The session
/// owns the timers and the model calls; everything here is testable
/// without either.
public enum SuggestionEngine {
    /// A session needs about two minutes of real conversation before
    /// a tip can be grounded in it.
    public static let warmUp: TimeInterval = 120
    /// Fewer lines than this from the other side is small talk, not
    /// material for a tip.
    public static let minimumThemSegments = 3

    public static func shouldEvaluate(now: Date, sessionStartedAt: Date, lastCycleAt: Date?, frequency: SuggestionFrequency, themSegmentCount: Int) -> Bool {
        guard frequency != .off else { return false }
        guard themSegmentCount >= minimumThemSegments else { return false }
        guard now.timeIntervalSince(sessionStartedAt) >= warmUp else { return false }
        if let lastCycleAt, now.timeIntervalSince(lastCycleAt) < frequency.cadence { return false }
        return true
    }

    /// A candidate that mostly repeats a tip already given this
    /// session is a duplicate, however it is worded. Word containment,
    /// the same trick the echo filter uses on transcript lines.
    public static func isDuplicate(_ text: String, previous: [String]) -> Bool {
        let words = ContextRanker.words(text)
        guard words.count >= 3 else { return false }
        for earlier in previous {
            let earlierWords = ContextRanker.words(earlier)
            guard !earlierWords.isEmpty else { continue }
            let shared = words.intersection(earlierWords).count
            let containment = Double(shared) / Double(min(words.count, earlierWords.count))
            if containment >= 0.6 { return true }
        }
        return false
    }

    /// The drafting model answers with one JSON object per line, but
    /// small models fence, indent, and wrap. Scan for balanced brace
    /// spans and decode each one that carries a kind and a text.
    public static func parseCandidates(_ raw: String) -> [Suggestion] {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "NONE" { return [] }
        var found: [Suggestion] = []
        var depth = 0
        var start: String.Index?
        for index in raw.indices {
            let character = raw[index]
            if character == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let spanStart = start {
                    let span = String(raw[spanStart...index])
                    if let suggestion = decodeCandidate(span) { found.append(suggestion) }
                    start = nil
                }
            }
        }
        return Array(found.prefix(3))
    }

    private static func decodeCandidate(_ span: String) -> Suggestion? {
        guard let data = span.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kindName = object["kind"] as? String,
              let kind = Suggestion.Kind(modelName: kindName),
              let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let why = (object["why"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Suggestion(kind: kind, text: text, why: why)
    }

    /// The filter answers with one word: PICK n, or NONE. Anything
    /// else, including a pick outside the candidate list, keeps none.
    public static func parsePick(_ raw: String, candidates: [Suggestion]) -> Suggestion? {
        let upper = raw.uppercased()
        guard let pickRange = upper.range(of: "PICK") else { return nil }
        let tail = upper[pickRange.upperBound...]
        guard let numberText = tail.split(whereSeparator: { !$0.isNumber }).first,
              let number = Int(numberText),
              candidates.indices.contains(number - 1) else { return nil }
        return candidates[number - 1]
    }
}

/// The two prompts behind a suggestion: a generous drafter and a
/// strict filter. The filter is the product; the bar moves with the
/// frequency the user picked.
public enum SuggestionPrompts {
    public static let draftSystem = """
        You are a quiet coach watching a live conversation, coaching one participant: the one labelled Me. \
        Every so often you offer one small tip that helps right now: a question worth asking, a follow up on \
        something just said, a detail from earlier that matters and was missed, or a better way to phrase a \
        sensitive point. Write up to 3 candidate tips. Each tip is one line the person can say out loud word \
        for word, or one thing to notice. Add one short line on why it helps at this moment. Tag each tip with \
        a kind: ask, follow-up, missed, or framing. Reply with one JSON object per line and nothing else, in \
        this shape: {"kind": "ask", "text": "the line to say", "why": "why it helps now"}. No introduction and \
        no commentary. If nothing in the conversation earns a tip, reply with the single word NONE.
        """

    public static func draftUser(modeName: String, transcript: String, previousTips: [String], context: String = "") -> String {
        var user = "Session type: \(modeName)"
        if !context.isEmpty {
            // What the user said this session is, at setup: who it is
            // with and what it is about. Hedy's own guidance says this
            // per-session context is what makes tips land; the mode
            // name alone is too coarse.
            user += "\nSession context: \(context)"
        }
        user += "\n\nRecent conversation (Them is the other side, Me is the person you coach):\n\(transcript)"
        if !previousTips.isEmpty {
            user += "\n\nTips already given this session, do not repeat these:\n" + previousTips.map { "- \($0)" }.joined(separator: "\n")
        }
        user += "\n\nWrite the candidate tips now."
        return user
    }

    public static func scoreSystem(frequency: SuggestionFrequency) -> String {
        let bar: String
        switch frequency {
        case .selective: bar = "The bar is high: keep a tip only if it could change the next minute of this conversation."
        case .frequent: bar = "Keep a tip when it is reasonably useful. When in doubt, answer NONE."
        default: bar = "Keep a tip when it is clearly useful. When in doubt, answer NONE."
        }
        return """
            You filter live coaching tips before they reach the person being coached. Most candidate tips are \
            not worth an interruption. Pick the one tip that is specific to what was just said, usable word for \
            word, and not already obvious to the person. \(bar) Reply with only PICK 1, PICK 2 or PICK 3 to keep \
            one tip, or NONE to keep none.
            """
    }

    public static func scoreUser(candidates: [Suggestion], transcript: String) -> String {
        let list = candidates.enumerated().map { index, tip in
            "\(index + 1). [\(tip.kind.tag)] \(tip.text) (\(tip.why))"
        }.joined(separator: "\n")
        return "Recent conversation:\n\(transcript)\n\nCandidate tips:\n\(list)\n\nPick one or answer NONE."
    }
}
