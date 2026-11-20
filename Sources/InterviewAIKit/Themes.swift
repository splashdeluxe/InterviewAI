import Foundation

/// One theme of a call: a topic the conversation actually spent
/// time on, named in a few words, with one line on what was said
/// about it and the moments it came up. The moments ride along as
/// seconds from the session start, the position the meeting's
/// audio player seeks to, so a theme can be checked against what
/// was actually said instead of trusted.
///
/// The shape is borrowed from Ashby's notetaker, whose Notes are
/// a summary plus themes with clickable timestamps. Here the
/// themes sit under the summary on the Summary tab, and they are
/// fenced like everything else the deep model writes (see
/// ThemeParsing): a theme survives only with at least one moment
/// inside the real call, duplicates collapse, and the prompts
/// forbid inventing a topic the transcript never raised.
public struct MeetingTheme: Codable, Equatable, Sendable {
    public var title: String
    public var detail: String
    public var atSeconds: [Double]

    public init(title: String, detail: String, atSeconds: [Double]) {
        self.title = title
        self.detail = detail
        self.atSeconds = atSeconds
    }

    /// Meetings store their themes as one JSON string.
    public static func encode(_ themes: [MeetingTheme]) -> String {
        guard let data = try? JSONEncoder().encode(themes) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func decode(_ json: String) -> [MeetingTheme] {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MeetingTheme].self, from: data) else { return [] }
        return decoded
    }
}

/// The two passes that find a call's themes. The first pass reads
/// one chunk of a finished transcript and collects candidate
/// themes. The second pass (ThemeMergePrompts) merges the
/// candidates from every chunk into the final short list, pooling
/// the moments of themes that turned out to be the same topic.
/// Both passes share the same guardrails: only topics the
/// transcript actually raises, never invent a subject, a number,
/// or a decision, and write in the language the conversation was
/// held in.
public enum ThemePrompts {
    public static let system = """
        You are reading one part of a finished call's transcript to name its themes: the topics this \
        part actually spent time on. For each theme give "t": a short title of two to five words, \
        "d": one full sentence on what was said about it, and "at": the moments it came up, as a list \
        of one to three numbers. Each transcript line starts with its moment as [seconds], a plain \
        number like [305]; copy those numbers exactly into "at", never convert them and never use a \
        line's position instead. Skip greetings, small talk, and scheduling chatter; a theme is a \
        subject the conversation worked on, not a pleasantry it passed through. Only write what this \
        part of the transcript shows. Never invent a topic, a number, a decision, or a claim, and \
        never credit a speaker with another speaker's words. Write in the language the conversation \
        was held in, even though this instruction is in English. Reply with JSON only, no code \
        fences, no commentary: {"themes": [{"t": "the title", "d": "what was said", "at": [0]}]}. \
        A part with no real topic is an empty list.
        """

    public static func user(transcript: String) -> String {
        "Transcript:\n\(transcript)"
    }
}

public enum ThemeMergePrompts {
    public static let system = """
        You are merging candidate themes collected across a whole call into the call's final theme \
        list. Combine candidates that name the same topic: keep the clearest title, write the \
        detail as one full sentence covering what was said across the call, and pool their moments, \
        earliest first. Keep the final list to between three and six themes, the topics the call \
        spent the most time on first, and drop anything that was only a passing mention. Base the \
        list only on the candidates given; never invent a topic, a number, or a decision that is \
        not in them, and keep every moment exactly as given. Write in the same language as the \
        candidates. Reply with JSON only, no code fences, no commentary: {"themes": [{"t": "the \
        title", "d": "what was said", "at": [0]}]}.
        """

    public static func user(title: String, modeName: String, themesJSON: String) -> String {
        "Call: \(title)\nMode: \(modeName)\nCandidate themes:\n\(themesJSON)"
    }
}

/// Turning a model's theme JSON into fenced themes. A theme
/// survives only when its title and detail carry substance and at
/// least one of its moments lands inside the call, so a theme
/// resting on a moment that never happened is dropped whole.
/// Duplicate titles collapse, moments are deduped and sorted, and
/// the list is capped, so a rambling reply cannot flood the page.
public enum ThemeParsing {
    private struct RawTheme: Codable {
        var t: String = ""
        var d: String = ""
        var at: [Double] = []

        init(t: String = "", d: String = "", at: [Double] = []) {
            self.t = t
            self.d = d
            self.at = at
        }

        private enum CodingKeys: String, CodingKey {
            case t, d, at
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            t = try container.decodeIfPresent(String.self, forKey: .t) ?? ""
            d = try container.decodeIfPresent(String.self, forKey: .d) ?? ""
            // A single moment handed back as one number instead of
            // a list still counts; small models do both.
            if let list = try? container.decode([Double].self, forKey: .at) {
                at = list
            } else if let single = try? container.decode(Double.self, forKey: .at) {
                at = [single]
            } else {
                at = []
            }
        }
    }

    private struct RawThemes: Codable {
        var themes: [RawTheme] = []

        init(themes: [RawTheme] = []) {
            self.themes = themes
        }

        private enum CodingKeys: String, CodingKey {
            case themes
        }

        /// One bad element (a number where the title belongs, a
        /// detail handed back as a list) must not sink the whole
        /// reply, so each element decodes on its own and the ones
        /// that fail are dropped before the fence ever sees them.
        private struct LossyTheme: Decodable {
            let value: RawTheme?

            init(from decoder: Decoder) throws {
                value = try? RawTheme(from: decoder)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let lossy = try container.decodeIfPresent([LossyTheme].self, forKey: .themes) ?? []
            themes = lossy.compactMap(\.value)
        }
    }

    /// The model's reply, read as forgivingly as a small local
    /// model needs: prose around the JSON, a bare list instead of
    /// the object, and even a reply cut off mid-theme are all
    /// tried before the reply is given up as unreadable. A reply
    /// that decodes but holds nothing returns an empty list, not
    /// nil: "looked, no themes" is a result, while nil means the
    /// reply could not be read at all.
    public static func parse(_ raw: String, maxSeconds: Double) -> [MeetingTheme]? {
        // A reading that yields themes beats one that yields
        // none: a bare list's first object slice decodes as an
        // empty themes object, and only the wrapped reading
        // further down the list finds the themes themselves.
        var emptyResult: [MeetingTheme]?
        for candidate in jsonCandidates(in: raw) {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(RawThemes.self, from: data) else { continue }
            let fenced = fence(decoded, maxSeconds: maxSeconds)
            if !fenced.isEmpty { return fenced }
            if emptyResult == nil { emptyResult = fenced }
        }
        return emptyResult
    }

    /// The readings of a reply worth trying, most faithful first:
    /// the widest object slice, each balanced object block on its
    /// own (prose can carry braces of its own), a bare list
    /// wrapped into the object shape, and a truncation salvage
    /// that keeps every theme the reply finished before it ran
    /// out of room.
    static func jsonCandidates(in raw: String) -> [String] {
        var out: [String] = []
        func add(_ candidate: String) {
            if !candidate.isEmpty, !out.contains(candidate) { out.append(candidate) }
        }
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end {
            add(String(raw[start...end]))
        }
        for block in balancedObjects(in: raw) { add(block) }
        if let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"), start < end {
            add("{\"themes\":\(String(raw[start...end]))}")
        }
        if raw.contains("\"themes\""), let end = raw.lastIndex(of: "}") {
            add(String(raw[...end]) + "]}")
        }
        return out
    }

    /// Every top-level balanced "{...}" block in the text, in
    /// order, skipping braces inside quoted strings.
    static func balancedObjects(in text: String) -> [String] {
        var blocks: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    blocks.append(String(text[s...i]))
                    start = nil
                } else if depth < 0 {
                    depth = 0
                }
            }
            i = text.index(after: i)
        }
        return blocks
    }

    /// The fence itself: substance, real moments, no duplicates.
    private static func fence(_ decoded: RawThemes, maxSeconds: Double) -> [MeetingTheme] {
        var seen: Set<String> = []
        var kept: [MeetingTheme] = []
        for theme in decoded.themes {
            let title = theme.t.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = theme.d.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 3, detail.count >= 12 else { continue }
            // A moment must be inside the call, with a minute of
            // slack for a marker read loosely; a theme left with
            // no moment at all does not survive.
            let moments = Array(Set(theme.at.filter { $0 >= 0 && $0 <= maxSeconds + 60 })).sorted()
            guard !moments.isEmpty else { continue }
            guard seen.insert(QuestionExtraction.normalize(title)).inserted else { continue }
            kept.append(MeetingTheme(title: title, detail: detail, atSeconds: Array(moments.prefix(6))))
            if kept.count >= 6 { break }
        }
        return kept
    }

    /// The candidate themes from every chunk, re-encoded as the
    /// merge pass's input, in the same shape the prompts describe.
    public static func encodeThemes(_ themes: [MeetingTheme]) -> String {
        let raw = RawThemes(themes: themes.map { RawTheme(t: $0.title, d: $0.detail, at: $0.atSeconds) })
        guard let data = try? JSONEncoder().encode(raw) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
