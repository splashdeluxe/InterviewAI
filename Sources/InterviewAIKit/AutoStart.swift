import Foundation

/// Auto-start: when a calendar event that is a video call begins,
/// InterviewAI offers to start listening on its own, with a short
/// countdown the user can stop. This file holds the two decisions
/// that must never misfire, kept pure so they are testable:
///
/// - Is this event a video call at all? Only an event carrying a
///   call link from a known host counts. A room, an address, a
///   birthday, a padel match: none of them can start a recording,
///   because none of them carries one of these links.
/// - Should it fire right now? The event must be inside its own
///   window (started, not yet ended), not all-day, not already
///   handled (fired or dismissed), and no session may be running.
///
/// The app side owns the clock, the countdown, and the panel; this
/// enum only answers questions about events.
public enum AutoStart {
    /// Hosts whose links mean "join a video call". Matched exactly
    /// or as a parent domain, so regional and numbered subdomains
    /// (us02web.zoom.us, app.webex.com) count.
    private static let callHosts = [
        "zoom.us", "zoom.com",
        "meet.google.com",
        "teams.microsoft.com", "teams.live.com",
        "webex.com",
        "whereby.com",
        "around.co",
        "chime.aws",
        "gotomeeting.com",
    ]

    /// The call link an event carries, if any: the event's own URL
    /// field first, then a link inside the location, then one inside
    /// the notes. The returned string is the link as written.
    public static func callLink(in event: UpcomingEvent) -> String? {
        for field in [event.url, event.location, event.details] {
            for candidate in links(in: field) where isCallLink(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The event to auto-start for, if one is due: inside its
    /// window, carrying a call link, not handled yet, and nothing
    /// listening. The earliest start wins, so a call that began
    /// while the app was closed still offers itself when the app
    /// opens mid-call, ahead of one that started later.
    public static func candidate(events: [UpcomingEvent], now: Date, handled: Set<String>, isListening: Bool) -> UpcomingEvent? {
        guard !isListening else { return nil }
        return events
            .filter { !$0.isAllDay && !handled.contains($0.id) && $0.start <= now && now < $0.end && callLink(in: $0) != nil }
            .sorted { $0.start < $1.start }
            .first
    }

    private static func isCallLink(_ raw: String) -> Bool {
        guard let host = URLComponents(string: raw)?.host?.lowercased() else { return false }
        return callHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Every http(s) link written in a text field, in order, with
    /// the punctuation a sentence wraps around a link trimmed off
    /// the end.
    private static func links(in text: String) -> [String] {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'\]\)]+"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let found = Range(match.range, in: text) else { return nil }
            var link = String(text[found])
            while let last = link.last, ".,;:".contains(last) { link.removeLast() }
            return link.isEmpty ? nil : link
        }
    }
}
