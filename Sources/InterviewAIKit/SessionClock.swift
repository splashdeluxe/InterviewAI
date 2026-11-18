import Foundation

/// The session timeline with the pauses taken out. Segment offsets,
/// the saved meeting's duration, and the diarization windows all read
/// this clock, so a paused stretch never counts as session time: the
/// transcript clock freezes while the session is paused and picks up
/// where it left off when it resumes.
public struct SessionClock: Equatable {
    public let startedAt: Date
    public private(set) var pausedTotal: TimeInterval = 0
    public private(set) var pauseBeganAt: Date?

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    public var isPaused: Bool { pauseBeganAt != nil }

    /// Session seconds at a wall-clock moment: the time since the
    /// start, minus every finished pause and the one still running.
    public func elapsed(at now: Date) -> TimeInterval {
        var paused = pausedTotal
        if let pauseBeganAt {
            paused += max(0, now.timeIntervalSince(pauseBeganAt))
        }
        return max(0, now.timeIntervalSince(startedAt) - paused)
    }

    public mutating func beginPause(at now: Date) {
        guard pauseBeganAt == nil else { return }
        pauseBeganAt = now
    }

    public mutating func endPause(at now: Date) {
        guard let pauseBeganAt else { return }
        pausedTotal += max(0, now.timeIntervalSince(pauseBeganAt))
        self.pauseBeganAt = nil
    }
}
