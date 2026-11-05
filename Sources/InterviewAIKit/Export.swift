import Foundation

/// A transcript as a file the user keeps: markdown for reading and
/// sharing, plain text for anything else. Pure string building, so the
/// shape is tested and the save panel in the app only writes it out.
public enum TranscriptExport {
    /// Markdown document: title, when it ran, who was invited, where,
    /// then the conversation with a bold speaker per line, then the
    /// summary when there is one.
    public static func markdown(title: String, date: Date, attendees: [String], location: String, segments: [TranscriptSegment], summary: String) -> String {
        var lines: [String] = ["# \(title)", ""]
        lines.append("Date: \(date.formatted(date: .complete, time: .shortened))")
        if !attendees.isEmpty {
            lines.append("Invited: \(attendees.joined(separator: ", "))")
        }
        if !location.isEmpty {
            lines.append("Location: \(location)")
        }
        lines.append("")
        lines.append("## Transcript")
        lines.append("")
        for segment in segments where segment.isFinal {
            lines.append("**\(segment.speakerName):** \(segment.displayText)")
            lines.append("")
        }
        if !summary.isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(summary)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Plain text, same content without the marks.
    public static func plainText(title: String, date: Date, attendees: [String], location: String, segments: [TranscriptSegment], summary: String) -> String {
        var lines: [String] = [title, date.formatted(date: .complete, time: .shortened)]
        if !attendees.isEmpty {
            lines.append("Invited: \(attendees.joined(separator: ", "))")
        }
        if !location.isEmpty {
            lines.append("Location: \(location)")
        }
        lines.append("")
        lines.append(TranscriptSegment.plainText(segments))
        if !summary.isEmpty {
            lines.append("")
            lines.append(summary)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A safe file name from the meeting title and day, e.g.
    /// "KNIME-Interview-2026-11-05.md". Anything that is not a letter,
    /// number, or dash folds into a dash.
    public static func fileName(title: String, date: Date, extension ext: String = "md") -> String {
        let slug = title.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        var name = String(slug)
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if name.isEmpty { name = "Meeting" }
        let day = date.formatted(.iso8601.year().month().day())
        return "\(name)-\(day).\(ext)"
    }
}
