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
