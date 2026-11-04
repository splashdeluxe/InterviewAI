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
