import Foundation

/// One question the other side asked the user in a finished
/// session, with the answer the user actually gave. Questions get
/// their own field on the meeting, separated from the transcript
/// flow, so a call can be re-read as what was asked and what was
/// answered. Every pair is fenced against the real transcript
/// before it is stored (see QuestionExtraction): the question must
/// trace to a real line from the other side, and the answer must
/// trace to the user's own following lines, or it is dropped.
public struct QuestionPair: Codable, Equatable, Sendable {
    public var question: String
    public var asker: String
    public var answer: String
    /// Seconds from the session start to the question line, the
    /// position the meeting's audio player seeks to.
    public var atSeconds: Double

    public init(question: String, asker: String, answer: String, atSeconds: Double) {
        self.question = question
        self.asker = asker
        self.answer = answer
        self.atSeconds = atSeconds
    }

    /// Meetings store their questions as one JSON string.
    public static func encode(_ pairs: [QuestionPair]) -> String {
        guard let data = try? JSONEncoder().encode(pairs) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(_ json: String) -> [QuestionPair] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([QuestionPair].self, from: data) else { return [] }
        return decoded
    }
}

/// The extraction prompt: the deep model reads a finished
/// transcript and returns the questions as JSON. The quotes must
/// be word for word, because QuestionExtraction matches them back
/// to the real lines; anything it cannot trace is dropped there,
/// so an invented question or answer never reaches the meeting.
public enum QuestionPrompts {
    public static let system = """
        You read the transcript of a finished conversation and find the questions the other side asked the user. \
        The user is the speaker labelled "Me". A question counts when the other side asks the user something and \
        waits for an answer: a direct question, or a request like "tell me about yourself". Back-channels like \
        "mm-hmm" or "yeah?", rhetorical questions, and questions the user asked do not count. Statements, plans, \
        greetings, news, and small talk are not questions, even when they end with "okay?" or "right?". When in \
        doubt, leave it out. For each question, \
        give the answer the user actually gave: their own following lines, joined, word for word. If the user \
        never answered, give an empty answer. Quote both word for word from the transcript; never polish, never \
        invent, never merge two questions into one. Reply with a JSON array only, no code fences, no commentary: \
        [{"q": "the question, word for word", "a": "the answer, word for word, or empty"}]. \
        If there are no questions, reply [].
        """

    public static func user(transcript: String) -> String {
        "Transcript:\n\(transcript)"
    }
}

/// Turning the model's JSON into fenced question pairs. A pair
/// survives only when its question quote matches a real line from
/// the other side (one line, or up to three lines in a row when a
/// question runs over several), when the matched lines carry
/// question evidence (a question mark, a question word, or a
/// question's verb-first opening), and when its answer quote's
/// words are found in the user's own lines that follow. The
/// asker and the timestamp always come from the matched line
/// itself, never from the model.
public enum QuestionExtraction {
    private struct Candidate: Decodable {
        let q: String
        let a: String?
    }

    public static func pairs(from raw: String, segments: [TranscriptSegment]) -> [QuestionPair] {
        guard let candidates = decodeCandidates(raw) else { return [] }
        let finals = segments.filter(\.isFinal)
        guard !finals.isEmpty else { return [] }
        let firstAt = finals[0].at
        var usedStarts: Set<Int> = []
        var seenQuestions: Set<String> = []
        var found: [QuestionPair] = []

        for candidate in candidates {
            let question = candidate.q.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedQuestion = normalize(question)
            // A real question is a handful of words; a two-word
            // quote would match half the transcript.
            guard normalizedQuestion.count >= 10 else { continue }
            // The same question quoted twice is one question,
            // however many spans it matched.
            guard seenQuestions.insert(normalizedQuestion).inserted else { continue }
            guard let span = matchSpan(normalizedQuestion, in: finals, skipping: usedStarts) else { continue }
            guard hasQuestionEvidence(span: span, in: finals, normalizedQuestion: normalizedQuestion) else { continue }
            usedStarts.insert(span.start)
            let questionSegment = finals[span.start]
            let answer = verifiedAnswer(candidate.a ?? "", after: span.end, in: finals)
            found.append(QuestionPair(
                question: question,
                asker: questionSegment.speakerName,
                answer: answer,
                atSeconds: questionSegment.startOffset ?? questionSegment.at.timeIntervalSince(firstAt)
            ))
        }
        return found.sorted { $0.atSeconds < $1.atSeconds }
    }

    /// The model's reply with any fences or prose around the JSON
    /// array stripped: the array is the text from the first "["
    /// to the last "]".
    private static func decodeCandidates(_ raw: String) -> [Candidate]? {
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"), start < end else { return nil }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Candidate].self, from: data)
    }

    /// Letters and digits only, lowercased, one space between
    /// words: the shape two quotes are compared in, so punctuation
    /// and casing from the speech engine never break a match.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        var scalars: [Unicode.Scalar] = []
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            } else {
                scalars.append(" ")
            }
        }
        return String(String.UnicodeScalarView(scalars))
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The span of final segments a question quote traces to: one
    /// line from the other side, or up to three in a row when the
    /// question runs over several lines. A match is containment
    /// either way, quote in lines or lines in quote.
    private static func matchSpan(_ normalizedQuestion: String, in finals: [TranscriptSegment], skipping usedStarts: Set<Int>) -> (start: Int, end: Int)? {
        for start in finals.indices {
            guard finals[start].channel == "them", !usedStarts.contains(start) else { continue }
            var joined = ""
            for end in start..<min(start + 3, finals.count) {
                guard finals[end].channel == "them" else { break }
                let line = normalize(finals[end].text)
                joined = joined.isEmpty ? line : joined + " " + line
                if joined.count >= 10, joined.contains(normalizedQuestion) || normalizedQuestion.contains(joined) {
                    return (start, end)
                }
            }
        }
        return nil
    }

    /// A matched quote still has to look like a question. The
    /// speech engine drops question marks often enough that the
    /// mark alone cannot be the test, so the words carry it too:
    /// a question word anywhere in the quote, or the verb-first
    /// opening a question has in German and English, or a direct
    /// request verb. A plain statement the model proposed anyway
    /// ("I am all packed already") fails all three and is dropped.
    private static func hasQuestionEvidence(span: (start: Int, end: Int), in finals: [TranscriptSegment], normalizedQuestion: String) -> Bool {
        let spanText = finals[span.start...span.end].map(\.text).joined(separator: " ")
        if spanText.contains("?") { return true }
        let words = normalizedQuestion.components(separatedBy: " ")
        guard let first = words.first else { return false }
        if requestVerbs.contains(first) || openingVerbs.contains(first) { return true }
        return words.contains { questionWords.contains($0) }
    }

    private static let questionWords: Set<String> = [
        "wie", "was", "warum", "weshalb", "wieso", "wann", "wo", "wer", "wen", "wem",
        "welche", "welcher", "welchem", "welchen",
        "how", "what", "why", "when", "where", "who", "whom", "which",
    ]

    private static let openingVerbs: Set<String> = [
        "kannst", "könntest", "hast", "bist", "ist", "sind", "war", "wird", "würdest",
        "gibt", "darfst", "musst", "sollst",
        "can", "could", "would", "will", "do", "does", "did", "is", "are",
        "have", "has", "should",
    ]

    private static let requestVerbs: Set<String> = [
        "erzähl", "erzähle", "sag", "sage", "zeig", "zeige", "gib",
        "beschreib", "beschreibe", "erklär", "erkläre",
        "tell", "show", "give", "describe", "explain", "introduce",
    ]

    /// The answer the user gave, kept only when its words are
    /// found in the user's own lines after the question. At least
    /// three quarters of its words must appear there; an answer
    /// that fails is dropped, never shown, because a polished or
    /// invented answer is worse than none.
    private static func verifiedAnswer(_ rawAnswer: String, after spanEnd: Int, in finals: [TranscriptSegment]) -> String {
        let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnswer = normalize(answer)
        guard normalizedAnswer.count >= 4 else { return "" }
        var followingWords: Set<String> = []
        var seen = 0
        for index in (spanEnd + 1)..<finals.count {
            if seen >= 20 { break }
            seen += 1
            guard finals[index].channel == "me" else { continue }
            for word in normalize(finals[index].text).components(separatedBy: " ") {
                followingWords.insert(word)
            }
        }
        let answerWords = normalizedAnswer.components(separatedBy: " ")
        let present = answerWords.filter { followingWords.contains($0) }.count
        guard !answerWords.isEmpty, Double(present) / Double(answerWords.count) >= 0.75 else { return "" }
        return answer
    }
}
