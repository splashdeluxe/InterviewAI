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

    public init(id: String, title: String, start: Date, end: Date, attendees: [String], calendarName: String) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
        self.calendarName = calendarName
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
        return UpcomingEvent(
            id: event.eventIdentifier ?? id,
            title: event.title ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            attendees: event.attendees?.compactMap { $0.name } ?? [],
            calendarName: event.calendar?.title ?? ""
        )
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
        return events.map { event in
            UpcomingEvent(
                id: event.eventIdentifier ?? "\((event.startDate ?? .now).timeIntervalSince1970)-\(event.title ?? "untitled")",
                title: event.title ?? "Untitled event",
                start: event.startDate,
                end: event.endDate,
                attendees: event.attendees?.compactMap { $0.name } ?? [],
                calendarName: event.calendar?.title ?? ""
            )
        }
    }
}
