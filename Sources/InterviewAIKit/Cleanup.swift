import Foundation

/// Clean Transcript: a polished copy of a finished session's
/// transcript, written by the deep model on this Mac, kept beside
/// the original, never over it. The cleanup fixes spelling,
/// punctuation, and grammar without changing what was said, gives
/// the turns paragraph shape, strips stray markers like "[Music]",
/// and consolidates speakers the diarization split apart, using
/// the names the user confirmed and the people the summary names.
/// The prompts and the output parsing live here so they are unit
/// tested; the app only runs the model and stores the result.
public enum CleanTranscriptPrompts {
    public static let system = """
        You clean a meeting transcript. Fix spelling, punctuation, and grammar without changing what was said: \
        never add, drop, or reword a statement, and never summarize. Write one speaker turn per line, as "Name: text". \
        Use the confirmed speaker names given to you. When one person was split into several numbered speakers, \
        give all of their turns the one label that fits them. When the session summary names a participant and a \
        numbered speaker's turns are clearly that person, use their name; when it is not clear, keep the number. \
        Drop lines that are only a sound marker like [Music]. Reply with the cleaned transcript only: no introduction, no commentary, no code fences.
        """

    public static func user(confirmedNames: [String], attendees: [String], summary: String, transcript: String) -> String {
        var parts: [String] = []
        if !confirmedNames.isEmpty {
            parts.append("Confirmed speakers: \(confirmedNames.joined(separator: ", "))")
        }
        if !attendees.isEmpty {
            parts.append("Invited: \(attendees.joined(separator: ", "))")
        }
        if !summary.isEmpty {
            parts.append("Session summary, for who the participants are:\n\(String(summary.prefix(2_000)))")
        }
        parts.append("Transcript:\n\(transcript)")
        return parts.joined(separator: "\n\n")
    }
}

/// Turning the model's cleaned text back into segments. The lines
/// carry names, so the transcript import parser does the shape
/// work; this adds the cleanup-specific drops: code fences and
/// lines that are only a bracketed sound marker.
public enum CleanedTranscript {
    public static func segments(from raw: String, myName: String = "") -> [TranscriptSegment] {
        let kept = raw.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("```") { return false }
            return !isBracketOnly(trimmed)
        }
        return TranscriptImport.parse(kept.joined(separator: "\n"), myName: myName)
            .filter { !isBracketOnly($0.text.trimmingCharacters(in: .whitespaces)) }
    }

    /// "[Music]", "[Applause]", and their kin are not speech.
    static func isBracketOnly(_ text: String) -> Bool {
        text.hasPrefix("[") && text.hasSuffix("]") && !text.dropFirst().dropLast().contains("[")
    }
}
