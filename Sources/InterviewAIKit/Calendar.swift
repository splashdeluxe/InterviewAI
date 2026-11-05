import EventKit
import Foundation

/// One calendar event, read-only. InterviewAI reads the calendar to name
/// meetings and offer one-click starts; it never creates, edits, or
/// deletes an event.
public struct UpcomingEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var attendees: [String]
    public var calendarName: String
    /// Where the meeting happens: a room, an address, or a call link
    /// typed into the event's location field.
    public var location: String
    /// The event's own notes or description, when it has any.
    public var details: String
    /// A URL on the event (often the call link), separate from the
    /// location text.
    public var url: String
    public var organizer: String

    public init(id: String, title: String, start: Date, end: Date, attendees: [String], calendarName: String,
                location: String = "", details: String = "", url: String = "", organizer: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
        self.calendarName = calendarName
        self.location = location
        self.details = details
        self.url = url
        self.organizer = organizer
    }
}

/// Which calendar event a session belongs to, when the session was not
/// started from the event itself. A session usually runs inside its
/// event; starting a little early or running over is normal, so the
/// window is widened by a tolerance on both sides. The event with the
/// longest overlap wins; a tie goes to the earliest start.
public enum EventMatcher {
    public static func pick(events: [UpcomingEvent], sessionStart: Date, sessionEnd: Date, tolerance: TimeInterval = 30 * 60) -> UpcomingEvent? {
        let windowStart = sessionStart.addingTimeInterval(-tolerance)
        let windowEnd = sessionEnd.addingTimeInterval(tolerance)
        let candidates = events.filter { $0.end >= windowStart && $0.start <= windowEnd }
        return candidates.max { a, b in
            let overlapA = overlap(of: a, sessionStart, sessionEnd)
            let overlapB = overlap(of: b, sessionStart, sessionEnd)
            if overlapA != overlapB { return overlapA < overlapB }
            return a.start > b.start
        }
    }

    private static func overlap(of event: UpcomingEvent, _ start: Date, _ end: Date) -> TimeInterval {
        min(event.end, end).timeIntervalSince(max(event.start, start))
    }
}

public enum CalendarService {
    // A fresh store per call: EKEventStore is not Sendable, so a shared
    // static one fails Swift 6 concurrency checks in this target.
    private static var store: EKEventStore { EKEventStore() }

    /// "Granted", "Not asked", "Denied", or "Write only", for the
    /// Permissions settings row.
    public static func authorizationText() -> String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "Granted"
        case .notDetermined: return "Not asked"
        case .denied, .restricted: return "Denied"
        case .writeOnly: return "Write only"
        @unknown default: return "Unknown"
        }
    }

    public static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Ask for full (read) access. Returns whether it was granted.
    public static func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// One event by its identifier, for showing the calendar link on a
    /// saved meeting. Nil without access or when the event is gone.
    public static func event(id: String) -> UpcomingEvent? {
        guard hasFullAccess, !id.isEmpty, let event = store.event(withIdentifier: id) else { return nil }
        return map(event)
    }

    /// The event a session belongs to, found by its time window: the
    /// session does not have to be started from the event for the saved
    /// meeting to carry the event's name and people.
    public static func event(overlappingSessionStart start: Date, end: Date) -> UpcomingEvent? {
        guard hasFullAccess else { return nil }
        let from = start.addingTimeInterval(-60 * 60)
        let to = end.addingTimeInterval(60 * 60)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        let events = store.events(matching: predicate).map { map($0) }
        return EventMatcher.pick(events: events, sessionStart: start, sessionEnd: end)
    }

    /// Events from now until `days` ahead, earliest first. Empty without
    /// full access. All-day events are included; the views label them.
    public static func upcoming(days: Int = 7, limit: Int = 20) -> [UpcomingEvent] {
        guard hasFullAccess else { return [] }
        let start = Date.now
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
        return events.map { map($0) }
    }

    private static func map(_ event: EKEvent) -> UpcomingEvent {
        UpcomingEvent(
            id: event.eventIdentifier ?? "\((event.startDate ?? .now).timeIntervalSince1970)-\(event.title ?? "untitled")",
            title: event.title ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            attendees: event.attendees?.compactMap { $0.name } ?? [],
            calendarName: event.calendar?.title ?? "",
            location: event.location ?? "",
            details: event.notes ?? "",
            url: event.url?.absoluteString ?? "",
            organizer: event.organizer?.name ?? ""
        )
    }
}
