import Foundation

/// Maps diarization ranges onto transcript lines by time overlap, so a
/// panel call reads as Speaker 1 / Speaker 2 instead of one "Them".
/// Pure time math, no audio and no models, so it is unit tested.
public enum SpeakerAssigner {
    /// One stretch of one speaker's voice, in seconds on the session
    /// timeline.
    public struct Range: Sendable, Equatable {
        public var speaker: String
        public var start: Double
        public var end: Double

        public init(speaker: String, start: Double, end: Double) {
            self.speaker = speaker
            self.start = start
            self.end = end
        }
    }

    /// One label per window, in window order. Speakers are numbered by
    /// when they are first heard. A window with no overlapping range, or
    /// no timing at all, gets nil and keeps its plain channel name.
    public static func labels(windows: [(start: Double, end: Double)?], ranges: [Range]) -> [String?] {
        var firstHeard: [String: Double] = [:]
        for range in ranges {
            firstHeard[range.speaker] = min(firstHeard[range.speaker] ?? .infinity, range.start)
        }
        let ordered = firstHeard.sorted { $0.value < $1.value }.map { $0.key }
        var numbers: [String: Int] = [:]
        for (index, speaker) in ordered.enumerated() { numbers[speaker] = index + 1 }

        return windows.map { window in
            guard let window else { return nil }
            var best: (speaker: String, overlap: Double)?
            for range in ranges {
                let overlap = min(window.end, range.end) - max(window.start, range.start)
                if overlap > 0, overlap > (best?.overlap ?? 0) {
                    best = (range.speaker, overlap)
                }
            }
            guard let best, let number = numbers[best.speaker] else { return nil }
            return "Speaker \(number)"
        }
    }
}

/// Turning "Speaker 1" and "Them" into real names. A name is only
/// ever used when it comes from a source that already knows it: the
/// people invited to the calendar event, the name typed into the
/// setup sheet, or the user's own name in Settings. The model may
/// match a diarized speaker to one of those invited names, but only
/// from that list, and `parseMapping` enforces the list, so a name
/// can never be invented here.
public enum SpeakerNames {
    /// The people who could be on the other side, cleaned: trimmed,
    /// no blanks, no email addresses (an address is not a name), no
    /// duplicates, and never the user themself. The organizer counts
    /// as a candidate: on a one-to-one invite they are often the only
    /// other person named anywhere.
    public static func candidates(attendees: [String], organizer: String = "", myName: String = "") -> [String] {
        var result: [String] = []
        let mine = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        for raw in attendees + [organizer] {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("@") else { continue }
            if !mine.isEmpty {
                if name.lowercased() == mine.lowercased() { continue }
                // A one-word candidate that is the user's own first
                // name is the user, not a second person.
                if !name.contains(" "), name.lowercased() == firstName(of: mine).lowercased() { continue }
            }
            if result.contains(where: { $0.lowercased() == name.lowercased() }) { continue }
            result.append(name)
        }
        return result
    }

    /// The one other person, when the sources name exactly one. Two
    /// or more candidates means the app cannot know who is speaking,
    /// so it says so by returning nil rather than guessing.
    public static func singleOther(attendees: [String], organizer: String = "", myName: String = "") -> String? {
        let list = candidates(attendees: attendees, organizer: organizer, myName: myName)
        return list.count == 1 ? list[0] : nil
    }

    /// Everyone the invitation points at: the attendee list, the
    /// organizer, and the names mined from the invitation's own
    /// title and details, cleaned the same way as `candidates`
    /// (no addresses, never the user, no duplicates). Real
    /// invitations often carry an empty attendee list and put the
    /// people in the text instead: "Interview with Sharin Sörgel",
    /// "ML6 interview — Jan Sawallisch, …". A lone first name that
    /// a full name in the list already covers is dropped.
    public static func invitationCandidates(attendees: [String], organizer: String = "",
                                            title: String = "", details: String = "",
                                            myName: String = "") -> [String] {
        let pool = candidates(attendees: attendees + minedNames(title: title, details: details),
                              organizer: organizer, myName: myName)
        return pool.filter { name in
            name.contains(" ")
                || !pool.contains(where: { $0 != name && firstName(of: $0).lowercased() == name.lowercased() })
        }
    }

    /// Names written into an invitation's title and details, in the
    /// order found. Deterministic patterns only, no model: a name
    /// after "with" or "mit" (a list joined by +, & or "and" gives
    /// every name), a name after "arranged / organised / booked
    /// by", and the title pattern "— Name,". A mined name is only
    /// ever a candidate: the evidence pass and the user still
    /// decide who actually spoke.
    public static func minedNames(title: String, details: String) -> [String] {
        var found: [String] = []
        func add(_ name: String) {
            if !found.contains(where: { $0.lowercased() == name.lowercased() }) { found.append(name) }
        }
        for name in withPhrases(in: title) { add(name) }
        for name in dashNames(in: title) { add(name) }
        for name in withPhrases(in: details) { add(name) }
        return found
    }

    private static let nameParticles: Set<String> = ["von", "van", "de", "der", "den", "ten", "zu"]
    private static let nameStoplist: Set<String> = [
        "google", "zoom", "microsoft", "teams", "skype", "webex",
        "interview", "call", "meeting", "team", "group", "everyone",
        "birthday", "holiday", "senior", "junior", "product", "manager",
        "director", "head", "chief", "lead", "staff", "principal",
        "talent", "acquisition", "partner", "specialist", "founder",
        "operations", "engineering", "design", "marketing",
    ]

    /// Words of a text with sentence punctuation trimmed off the
    /// edges, so "(call" and "Mandry," read as plain words.
    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "(),.;:!?\"'„“”«»")) }
            .filter { !$0.isEmpty }
    }

    /// A word that can be part of a person's name: starts with an
    /// uppercase letter, is letters, hyphens and apostrophes only,
    /// is not an all-caps shout, and is not a platform, calendar or
    /// role word.
    private static func isNameWord(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        guard word.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return false }
        if word.count > 1, word.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return false }
        return !nameStoplist.contains(word.lowercased())
    }

    /// One name starting at `index`: a name word plus one more, or
    /// a name word, a lowercase particle (von, van, de) and a name
    /// word. Never more: a third plain word after two is where role
    /// words begin ("Sharin Sörgel, Senior Talent …"), and stopping
    /// there keeps them out.
    private static func parseName(in words: [String], at index: Int) -> (name: String, next: Int)? {
        guard index < words.count, isNameWord(words[index]) else { return nil }
        var parts = [words[index]]
        var cursor = index + 1
        if cursor < words.count {
            if nameParticles.contains(words[cursor].lowercased()),
               cursor + 1 < words.count, isNameWord(words[cursor + 1]) {
                parts.append(words[cursor])
                parts.append(words[cursor + 1])
                cursor += 2
            } else if isNameWord(words[cursor]) {
                parts.append(words[cursor])
                cursor += 1
            }
        }
        return (parts.joined(separator: " "), cursor)
    }

    /// Names that follow "with" / "mit", or "by" right after
    /// arranged / organised / organized / booked.
    private static func withPhrases(in text: String) -> [String] {
        let words = words(of: text)
        var names: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index].lowercased()
            let triggered = word == "with" || word == "mit"
                || (word == "by" && index > 0
                    && ["arranged", "organised", "organized", "booked"].contains(words[index - 1].lowercased()))
            guard triggered else { index += 1; continue }
            var cursor = index + 1
            while let parsed = parseName(in: words, at: cursor) {
                names.append(parsed.name)
                cursor = parsed.next
                if cursor < words.count, ["+", "&", "and", "und"].contains(words[cursor].lowercased()) {
                    cursor += 1
                } else { break }
            }
            index = max(cursor, index + 1)
        }
        return names
    }

    /// The title pattern "— Name,": "ML6 interview — Jan
    /// Sawallisch, Senior Product Manager". The name must be
    /// followed by a comma or the end of the segment.
    private static func dashNames(in title: String) -> [String] {
        var names: [String] = []
        for segment in title.components(separatedBy: "—").dropFirst() {
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            guard let parsed = parseName(in: words(of: trimmed), at: 0),
                  trimmed.hasPrefix(parsed.name) else { continue }
            let rest = trimmed.dropFirst(parsed.name.count)
            if rest.isEmpty || rest.hasPrefix(",") { names.append(parsed.name) }
        }
        return names
    }

    /// "Jan Sawallisch" becomes "Jan". Used where a full name would
    /// crowd a transcript label, and for the user's own lines.
    public static func firstName(of fullName: String) -> String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first.map(String.init) ?? ""
    }

    /// Rewrite speaker labels through a mapping keyed by the label
    /// the reader currently sees ("Them", "Speaker 1", "Me"). The
    /// mapped name becomes the segment's speaker label, so every
    /// surface that shows, exports, or prompts from the transcript
    /// picks it up with no further work.
    public static func applying(segments: [TranscriptSegment], mapping: [String: String]) -> [TranscriptSegment] {
        segments.map { segment in
            guard let name = mapping[segment.speakerName],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  name != segment.speakerName else { return segment }
            var copy = segment
            copy.speakerLabel = name
            return copy
        }
    }

    /// The distinct names a transcript currently shows, in the order
    /// first heard. The rename UI works from this list.
    public static func distinctNames(segments: [TranscriptSegment]) -> [String] {
        var seen: [String] = []
        for segment in segments where segment.isFinal {
            if !seen.contains(segment.speakerName) { seen.append(segment.speakerName) }
        }
        return seen
    }

    /// Read the model's answer to `SpeakerNamePrompts` and keep only
    /// what is provably allowed: the key must be one of the labels
    /// asked about, and the value must be one of the candidate names,
    /// returned in the candidate's own spelling. Anything else the
    /// model writes, including a name it made up, is dropped.
    public static func parseMapping(_ raw: String, labels: [String], candidates: [String]) -> [String: String] {
        var mapping: [String: String] = [:]
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
                    if let data = span.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                        for (label, value) in object {
                            guard labels.contains(label), mapping[label] == nil,
                                  let canonical = candidates.first(where: { $0.lowercased() == value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }),
                                  canonical != label else { continue }
                            mapping[label] = canonical
                        }
                    }
                    start = nil
                }
            }
        }
        return mapping
    }
}

/// What a meeting shows when speaker separation did not fully
/// happen. Silence here reads as "only one person spoke", which is
/// often wrong, so the outcome is written on the meeting in plain
/// words instead. One source for the wording, app and imports alike.
public enum DiarizationNotes {
    public static let tooShort = "Speaker labels are unavailable for this session: it was too short to separate the voices."
    public static let unavailable = "Speaker labels are unavailable for this session."
    public static let firstHourOnly = "Speakers were checked for the first hour only; later voices keep the plain labels."
}

/// The voices on the other side of a meeting, grouped for the
/// confirm step. Diarization separates voices by sound, not by
/// person, so one person can land in two groups and some lines get
/// no group at all. Only the user knows who was actually in the
/// meeting, so the groups are presented for confirmation and the
/// fix is a rename through `SpeakerNames.applying`: naming two
/// groups the same merges them, and naming the unnamed group
/// ("Them") gives those lines a speaker too.
public enum SpeakerConfirmation {
    /// One voice as the transcript currently presents it.
    public struct Voice: Equatable, Sendable {
        /// The label the reader sees now: a real name, "Speaker N",
        /// or "Them" for the lines no voice claimed.
        public var name: String
        public var lineCount: Int
        /// The first line this voice said, so the user can recognise
        /// them without playing anything.
        public var sample: String
        /// Where the first line starts in the saved audio, for a
        /// listen-to-this-voice button. Nil when the line has no
        /// timing.
        public var firstOffset: Double?

        public init(name: String, lineCount: Int, sample: String, firstOffset: Double?) {
            self.name = name
            self.lineCount = lineCount
            self.sample = sample
            self.firstOffset = firstOffset
        }
    }

    /// The other side's voices in first-heard order: the voice
    /// clusters diarization actually found, named or numbered.
    /// Lines no voice claimed are not a speaker; they are reported
    /// separately by `unassigned(in:)`. Only final lines on the
    /// "them" channel count; the user's own lines are never part
    /// of the confirmation.
    public static func voices(in segments: [TranscriptSegment]) -> [Voice] {
        var order: [String] = []
        var grouped: [String: Voice] = [:]
        for segment in segments where segment.isFinal && segment.channel == "them" {
            guard let label = segment.speakerLabel else { continue }
            if var voice = grouped[label] {
                voice.lineCount += 1
                grouped[label] = voice
            } else {
                order.append(label)
                grouped[label] = Voice(name: label, lineCount: 1,
                                       sample: segment.displayText,
                                       firstOffset: segment.startOffset)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    /// The other side's lines that no voice claimed: diarization
    /// never covered them, so they say nothing about how many
    /// speakers there were. They still need an owner, which the
    /// confirmation can give them without counting them as one
    /// more speaker.
    public struct Unassigned: Equatable, Sendable {
        public var lineCount: Int
        public var sample: String
        public var firstOffset: Double?

        public init(lineCount: Int, sample: String, firstOffset: Double?) {
            self.lineCount = lineCount
            self.sample = sample
            self.firstOffset = firstOffset
        }
    }

    public static func unassigned(in segments: [TranscriptSegment]) -> Unassigned? {
        let loose = segments.filter { $0.isFinal && $0.channel == "them" && $0.speakerLabel == nil }
        guard let first = loose.first else { return nil }
        return Unassigned(lineCount: loose.count, sample: first.displayText,
                          firstOffset: first.startOffset)
    }

    /// A label the app made up rather than a person: the plain
    /// channel name, or a numbered diarization label.
    public static func isGeneric(_ name: String) -> Bool {
        if name == "Them" { return true }
        guard name.hasPrefix("Speaker ") else { return false }
        return Int(name.dropFirst("Speaker ".count)) != nil
    }

    /// Worth asking the user about: the other side spoke, and
    /// either more than one voice was found, a voice still carries
    /// a made-up label, or some lines have no voice at all. One
    /// voice with a real name and every line claimed needs no
    /// check.
    public static func needsConfirmation(segments: [TranscriptSegment]) -> Bool {
        let found = voices(in: segments)
        let loose = unassigned(in: segments)
        guard !found.isEmpty || loose != nil else { return false }
        return found.count > 1 || loose != nil || found.contains { isGeneric($0.name) }
    }
}

/// The one model call that may match diarized speakers to invited
/// names, after a call. The bar is evidence inside the transcript:
/// an introduction, a self-reference, being addressed by name. The
/// parser above still has the last word, so even a confident answer
/// cannot name anyone who was not invited.
public enum SpeakerNamePrompts {
    public static let system = """
        You match speaker labels in a meeting transcript to the real names of the people who were invited. \
        Map a label only when the transcript itself proves who that speaker is: the speaker introduces themself, \
        another speaker addresses them by that name, or they refer to their own name or role in a way that fits only that person. \
        When the proof is not there, leave the label out. Never guess from speaking order or speaking time. \
        Reply with only one JSON object mapping label to name, like {"Speaker 1": "Jan Sawallisch"}. If nothing is proven, reply {}.
        """

    public static func user(labels: [String], candidates: [String], transcript: String) -> String {
        """
        Speakers to name: \(labels.joined(separator: ", "))
        People who were invited: \(candidates.joined(separator: ", "))

        Transcript:
        \(String(transcript.prefix(12_000)))
        """
    }
}
