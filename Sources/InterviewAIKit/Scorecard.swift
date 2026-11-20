import Foundation

/// One point on the interviewer's scorecard: a short note in the
/// interviewer's own words, resting on one moment of the call.
/// The moment rides along as seconds from the session start, the
/// position the meeting's audio player seeks to, so every point
/// can be checked against what was actually said.
public struct ScorecardPoint: Codable, Equatable, Sendable {
    public var text: String
    public var atSeconds: Double

    public init(text: String, atSeconds: Double) {
        self.text = text
        self.atSeconds = atSeconds
    }
}

/// The scorecard the other side would plausibly file on the user
/// after this call: what they probed, the strongest evidence the
/// user gave, where the answers were thin, and the overall read.
/// Ashby's notetaker drafts feedback text for hiring teams but is
/// built to never rate or judge; a personal, local tool has no
/// such constraint, and the judgement is the point here. It is
/// still fenced (see ScorecardParsing): every point must carry a
/// timestamp inside the real call, duplicates collapse, and the
/// prompts forbid inventing anything the transcript does not show.
public struct InterviewScorecard: Codable, Equatable, Sendable {
    public var probed: [ScorecardPoint]
    public var evidence: [ScorecardPoint]
    public var gaps: [ScorecardPoint]
    /// The overall read, one or two sentences, written last from
    /// the merged points.
    public var verdict: String

    public init(probed: [ScorecardPoint], evidence: [ScorecardPoint], gaps: [ScorecardPoint], verdict: String) {
        self.probed = probed
        self.evidence = evidence
        self.gaps = gaps
        self.verdict = verdict
    }

    public var isEmpty: Bool {
        probed.isEmpty && evidence.isEmpty && gaps.isEmpty && verdict.isEmpty
    }

    /// Meetings store their scorecard as one JSON string.
    public static func encode(_ card: InterviewScorecard) -> String {
        guard let data = try? JSONEncoder().encode(card) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(_ json: String) -> InterviewScorecard? {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(InterviewScorecard.self, from: data) else { return nil }
        return decoded
    }
}

/// The two passes that write a scorecard. The first pass reads
/// one chunk of a finished transcript and collects raw points in
/// the interviewer's voice. The second pass (ScorecardMerge
/// Prompts) merges the points from every chunk, drops the
/// duplicates, and writes the verdict. Both passes share the same
/// guardrails: only what the transcript shows, never invent a
/// credential, a number, or a claim, and write in the language
/// the conversation was held in.
public enum ScorecardPrompts {
    public static let system = """
        You are the interviewer on a finished call, writing the private notes you would file on the \
        person you interviewed (the speaker labelled "Me"). Read this part of the transcript and note \
        three things. "probed": what you set out to test here, the areas and questions you pressed on. \
        "evidence": the strongest proof the person gave, concrete things they said they did, built, or \
        decided. "gaps": where an answer was thin, vague, evasive, or missing proof you asked for. \
        Every point is one full short sentence in your own words, the way you would write it in a \
        feedback form, and every point carries "at": the moment it rests on. Each transcript line \
        starts with its moment as [seconds], a plain number like [305]; copy that number exactly as \
        "at", never convert it and never use a line's position instead. Only write what this part of \
        the transcript shows. Never invent a credential, a number, a result, or a claim, and never \
        credit the person with something another speaker said. Write every point in the language the \
        conversation was held in, even though this instruction is in English. Reply with JSON only, \
        no code fences, no commentary: {"probed": [{"t": "the point", "at": 0}], "evidence": [], \
        "gaps": []}. A section with nothing in this part is an empty array.
        """

    public static func user(transcript: String) -> String {
        "Transcript:\n\(transcript)"
    }
}

public enum ScorecardMergePrompts {
    public static let system = """
        You are the interviewer on a finished call, merging your own rough notes into the scorecard \
        you would file on the person you interviewed. You are given the points collected across the \
        whole call, already grouped as probed, evidence, and gaps. Merge duplicates that say the \
        same thing, keep the sharpest wording, and keep each surviving point's "at" seconds exactly \
        as given. Keep at most 6 probed, 5 evidence, and 5 gaps, strongest first. If an area was \
        probed but no evidence point answers it, add it to gaps in your own words, with the probed \
        point's "at". Then write "verdict": the overall read you would give a colleague, one or two \
        sentences, honest about both the strength and the thin places. Base the verdict only on the \
        points given; never invent a credential, a number, or an event that is not in them. Write in \
        the same language as the points. Reply with JSON only, no code fences, no commentary: \
        {"probed": [{"t": "the point", "at": 0}], "evidence": [], "gaps": [], "verdict": "the \
        overall read"}.
        """

    public static func user(title: String, modeName: String, pointsJSON: String) -> String {
        "Call: \(title)\nMode: \(modeName)\nCollected points:\n\(pointsJSON)"
    }
}

/// Turning a model's scorecard JSON into a fenced scorecard. A
/// point survives only when its text is a real line of substance
/// and its timestamp lands inside the call, so a point resting on
/// a moment that never happened is dropped. Duplicates collapse
/// by their words, and each section is capped, so a rambling
/// reply cannot flood the meeting page.
public enum ScorecardParsing {
    private struct RawPoint: Codable {
        let t: String
        let at: Double
    }

    private struct RawCard: Codable {
        var probed: [RawPoint] = []
        var evidence: [RawPoint] = []
        var gaps: [RawPoint] = []
        var verdict: String = ""

        // A missing section is an empty section, not a failed
        // decode: the model may leave out a section it found
        // nothing for, defaults notwithstanding.
        init(probed: [RawPoint] = [], evidence: [RawPoint] = [], gaps: [RawPoint] = [], verdict: String = "") {
            self.probed = probed
            self.evidence = evidence
            self.gaps = gaps
            self.verdict = verdict
        }

        private enum CodingKeys: String, CodingKey {
            case probed, evidence, gaps, verdict
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            probed = try container.decodeIfPresent([RawPoint].self, forKey: .probed) ?? []
            evidence = try container.decodeIfPresent([RawPoint].self, forKey: .evidence) ?? []
            gaps = try container.decodeIfPresent([RawPoint].self, forKey: .gaps) ?? []
            verdict = try container.decodeIfPresent(String.self, forKey: .verdict) ?? ""
        }
    }

    /// The model's reply with any fences or prose around the JSON
    /// object stripped: the object is the text from the first "{"
    /// to the last "}". A reply that decodes but holds nothing
    /// returns an empty card, not nil: "looked, nothing to file"
    /// is a result, while nil means the reply could not be read
    /// at all.
    public static func parse(_ raw: String, maxSeconds: Double) -> InterviewScorecard? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else { return nil }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawCard.self, from: data) else { return nil }
        return InterviewScorecard(
            probed: clean(decoded.probed, maxSeconds: maxSeconds, cap: 8),
            evidence: clean(decoded.evidence, maxSeconds: maxSeconds, cap: 6),
            gaps: clean(decoded.gaps, maxSeconds: maxSeconds, cap: 6),
            verdict: decoded.verdict.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// The collected points from every chunk, re-encoded as the
    /// merge pass's input. Encoding through the same RawCard shape
    /// the prompts describe keeps the two passes in one format.
    public static func encodePoints(probed: [ScorecardPoint], evidence: [ScorecardPoint], gaps: [ScorecardPoint]) -> String {
        let raw = RawCard(
            probed: probed.map { RawPoint(t: $0.text, at: $0.atSeconds) },
            evidence: evidence.map { RawPoint(t: $0.text, at: $0.atSeconds) },
            gaps: gaps.map { RawPoint(t: $0.text, at: $0.atSeconds) },
            verdict: ""
        )
        guard let data = try? JSONEncoder().encode(raw) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func clean(_ points: [RawPoint], maxSeconds: Double, cap: Int) -> [ScorecardPoint] {
        var seen: Set<String> = []
        var kept: [ScorecardPoint] = []
        for point in points {
            let text = point.t.trimmingCharacters(in: .whitespacesAndNewlines)
            // A point is a line of substance, not a fragment, and
            // its moment must be inside the call, with a minute of
            // slack for a marker read loosely.
            guard text.count >= 12 else { continue }
            guard point.at >= 0, point.at <= maxSeconds + 60 else { continue }
            guard seen.insert(QuestionExtraction.normalize(text)).inserted else { continue }
            kept.append(ScorecardPoint(text: text, atSeconds: point.at))
            if kept.count >= cap { break }
        }
        return kept
    }
}
