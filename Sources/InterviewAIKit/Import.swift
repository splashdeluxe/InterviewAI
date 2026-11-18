import Foundation

/// Bringing an existing conversation into the meeting history, the
/// three ways Hedy offers and this app mirrors: paste a transcript,
/// transcribe an audio or video file, or take a video link. The
/// parsing and classification here is pure and unit tested; the
/// downloads, file decoding, and model calls live in the app.
public enum TranscriptImport {
    /// Parse pasted transcript text into segments. A line that opens
    /// with a name and a colon ("Sharin Sörgel: Tell me about…")
    /// starts a new segment under that name; markdown bold around the
    /// name works too. Any other line continues the segment above it.
    /// A leading timestamp ("[12:34]" or "1:02:03") is read as the
    /// line's offset and stripped. Lines from the user themself (their
    /// name from Settings, or "Me") land on the mic channel; everyone
    /// else lands on the other side with their name as the label, so
    /// the speaker names survive the import.
    public static func parse(_ text: String, myName: String = "") -> [TranscriptSegment] {
        let mine = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        var segments: [TranscriptSegment] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            var offset: Double?
            if let stamp = leadingTimestamp(in: &line) { offset = stamp }
            if let (name, rest) = speakerPrefix(in: line), !rest.isEmpty {
                let isMe = isUsersLine(name: name, myName: mine)
                segments.append(TranscriptSegment(
                    channel: isMe ? "me" : "them",
                    text: rest,
                    isFinal: true,
                    speakerLabel: label(forName: name, isMe: isMe, myName: mine),
                    startOffset: offset
                ))
            } else if var last = segments.popLast() {
                last.text += " " + line
                segments.append(last)
            } else {
                segments.append(TranscriptSegment(channel: "them", text: line, isFinal: true, startOffset: offset))
            }
        }
        return segments
    }

    /// Seconds from a "12:34" or "1:02:03" timestamp, or nil when the
    /// token is not a timestamp.
    public static func parseTimestamp(_ token: String) -> Double? {
        let parts = token.split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count else { return nil }
        if numbers.count == 2 { return numbers[0] * 60 + numbers[1] }
        return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
    }

    /// A leading "[12:34]" or "12:34 " at the start of the line,
    /// removed from the line when found.
    private static func leadingTimestamp(in line: inout String) -> Double? {
        var rest = line
        var bracketed = false
        if rest.hasPrefix("[") {
            bracketed = true
            rest = String(rest.dropFirst())
        }
        guard let tokenEnd = rest.firstIndex(where: { $0 == "]" || $0 == " " || $0 == "\t" }) else { return nil }
        let token = String(rest[..<tokenEnd])
        guard let seconds = parseTimestamp(token) else { return nil }
        var remainder = String(rest[tokenEnd...])
        if bracketed {
            guard remainder.hasPrefix("]") else { return nil }
            remainder = String(remainder.dropFirst())
        }
        line = remainder.trimmingCharacters(in: .whitespaces)
        return seconds
    }

    /// "Name: rest of the line", with markdown bold tolerated around
    /// the name. The name may not contain a colon, may not be a URL,
    /// and is capped at a plausible name length.
    private static func speakerPrefix(in line: String) -> (name: String, rest: String)? {
        var text = line
        if text.hasPrefix("**") { text = String(text.dropFirst(2)) }
        guard let colon = text.firstIndex(of: ":") else { return nil }
        var name = String(text[..<colon])
        if name.hasSuffix("**") { name = String(name.dropLast(2)) }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 40, !name.contains("/"), !name.contains("\\") else { return nil }
        var rest = String(text[text.index(after: colon)...])
        if rest.hasPrefix("**") { rest = String(rest.dropFirst(2)) }
        rest = rest.trimmingCharacters(in: .whitespaces)
        return (name, rest)
    }

    private static func isUsersLine(name: String, myName: String) -> Bool {
        let lowered = name.lowercased()
        if lowered == "me" || lowered == "i" || lowered == "myself" { return true }
        guard !myName.isEmpty else { return false }
        return lowered == myName.lowercased()
            || lowered == SpeakerNames.firstName(of: myName).lowercased()
    }

    /// The label a parsed name becomes. Generic names stay generic:
    /// "Them" is no label at all, "Speaker 1" stays as it is, and the
    /// user's own lines carry their first name when it is known.
    private static func label(forName name: String, isMe: Bool, myName: String) -> String? {
        if isMe {
            let first = SpeakerNames.firstName(of: myName)
            return first.isEmpty ? nil : first
        }
        if name.lowercased() == "them" || name.lowercased() == "other" { return nil }
        return name
    }
}

/// Which import route a pasted link takes. Direct media links are
/// downloaded and treated as files; YouTube links are read through
/// the captions the platform publishes (Hedy falls back to the same
/// source); anything else is refused plainly rather than fetched on
/// a guess.
public enum ImportSource {
    public enum Kind: Equatable, Sendable {
        case directMedia
        case youTube(videoID: String)
        case unsupported
    }

    public static let mediaExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "ogg", "opus", "flac", "amr",
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "3gp",
    ]

    public static func classify(_ urlString: String) -> (kind: Kind, url: URL?) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return (.unsupported, nil) }
        if let videoID = youTubeVideoID(url) { return (.youTube(videoID: videoID), url) }
        if mediaExtensions.contains(url.pathExtension.lowercased()) { return (.directMedia, url) }
        return (.unsupported, url)
    }

    /// The video id from a youtube.com watch, shorts, live, or embed
    /// link, or a youtu.be short link. Nil for any other host.
    public static func youTubeVideoID(_ url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host == "youtu.be" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.path == "/watch", let id = components?.queryItems?.first(where: { $0.name == "v" })?.value, !id.isEmpty {
            return id
        }
        for prefix in ["/shorts/", "/live/", "/embed/"] where url.path.hasPrefix(prefix) {
            let id = String(url.path.dropFirst(prefix.count)).split(separator: "/").first.map(String.init) ?? ""
            return id.isEmpty ? nil : id
        }
        return nil
    }
}

/// YouTube's published captions (the timedtext "json3" format) as
/// transcript segments. Caption lines carry timing but no speakers,
/// so they land on the other side unnamed; the meeting's rename tools
/// and the summary work from there.
public enum CaptionSegments {
    public static func parse(json3 data: Data) -> [TranscriptSegment] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        var segments: [TranscriptSegment] = []
        for event in events {
            guard let parts = event["segs"] as? [[String: Any]] else { continue }
            let text = parts.compactMap { $0["utf8"] as? String }
                .joined(separator: "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !(text.hasPrefix("[") && text.hasSuffix("]")) else { continue }
            let start = (event["tStartMs"] as? Double ?? 0) / 1000
            let duration = (event["dDurationMs"] as? Double ?? 0) / 1000
            segments.append(TranscriptSegment(
                channel: "them", text: text, isFinal: true,
                startOffset: start, duration: duration
            ))
        }
        return segments
    }
}

/// Cutting one transcribed chunk of a file import into
/// sentence-sized segments, with timing spread across the chunk in
/// proportion to sentence length, so diarization and the meeting
/// view still get plausible windows per line.
public enum SegmentSplitter {
    public static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" || character == "…" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    public static func segments(text: String, chunkStart: Double, chunkDuration: Double) -> [TranscriptSegment] {
        let lines = sentences(text)
        guard !lines.isEmpty else { return [] }
        let total = Double(lines.reduce(0) { $0 + $1.count })
        guard total > 0 else { return [] }
        var cursor = chunkStart
        return lines.map { line in
            let share = Double(line.count) / total
            let duration = chunkDuration * share
            let segment = TranscriptSegment(
                channel: "them", text: line, isFinal: true,
                startOffset: cursor, duration: duration
            )
            cursor += duration
            return segment
        }
    }
}
