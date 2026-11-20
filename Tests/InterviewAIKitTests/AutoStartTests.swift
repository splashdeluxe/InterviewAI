import Foundation
import Testing
@testable import InterviewAIKit

private let autoNow = Date(timeIntervalSince1970: 1_700_000_000)

private func autoEvent(
    id: String = "e1",
    title: String = "Call",
    startOffset: TimeInterval = -300,
    endOffset: TimeInterval = 1800,
    location: String = "",
    details: String = "",
    url: String = "",
    isAllDay: Bool = false
) -> UpcomingEvent {
    UpcomingEvent(
        id: id, title: title,
        start: autoNow.addingTimeInterval(startOffset),
        end: autoNow.addingTimeInterval(endOffset),
        attendees: ["Petra"], calendarName: "Work",
        location: location, details: details, url: url,
        organizer: "", isAllDay: isAllDay
    )
}

@Test("A Zoom link in the location field is a call link")
func autoZoomInLocation() {
    let event = autoEvent(location: "https://us02web.zoom.us/j/123456789?pwd=abc")
    #expect(AutoStart.callLink(in: event) == "https://us02web.zoom.us/j/123456789?pwd=abc")
}

@Test("A Meet link buried in the event notes is a call link")
func autoMeetInDetails() {
    let event = autoEvent(details: "Join here: https://meet.google.com/abc-defg-hij — bring the numbers.")
    #expect(AutoStart.callLink(in: event) == "https://meet.google.com/abc-defg-hij")
}

@Test("A Teams link in the event URL field is a call link")
func autoTeamsInURLField() {
    let event = autoEvent(url: "https://teams.microsoft.com/l/meetup-join/19%3Ameeting_abc")
    #expect(AutoStart.callLink(in: event)?.hasPrefix("https://teams.microsoft.com") == true)
}

@Test("A room, an address, and a document link are not call links")
func autoNoLinkCases() {
    #expect(AutoStart.callLink(in: autoEvent(location: "Room 4, second floor")) == nil)
    #expect(AutoStart.callLink(in: autoEvent(location: "Jalan Sugriwa, Buwit")) == nil)
    #expect(AutoStart.callLink(in: autoEvent(details: "Agenda: https://docs.google.com/document/d/xyz")) == nil)
    #expect(AutoStart.callLink(in: autoEvent()) == nil)
}

@Test("An event inside its window with a call link is the candidate")
func autoCandidatePicked() {
    let event = autoEvent(location: "https://zoom.us/j/999")
    let picked = AutoStart.candidate(events: [event], now: autoNow, handled: [], isListening: false)
    #expect(picked?.id == "e1")
}

@Test("All-day events never auto-start, link or not")
func autoAllDaySkipped() {
    let event = autoEvent(location: "https://zoom.us/j/999", isAllDay: true)
    #expect(AutoStart.candidate(events: [event], now: autoNow, handled: [], isListening: false) == nil)
}

@Test("Handled events are skipped, and nothing fires while listening")
func autoHandledAndListening() {
    let event = autoEvent(location: "https://zoom.us/j/999")
    #expect(AutoStart.candidate(events: [event], now: autoNow, handled: ["e1"], isListening: false) == nil)
    #expect(AutoStart.candidate(events: [event], now: autoNow, handled: [], isListening: true) == nil)
}

@Test("Future and finished events are not candidates")
func autoWindowEdges() {
    let future = autoEvent(id: "f", startOffset: 600, endOffset: 3600, location: "https://zoom.us/j/1")
    let done = autoEvent(id: "d", startOffset: -7200, endOffset: -3600, location: "https://zoom.us/j/2")
    let plain = autoEvent(id: "p", location: "Office")
    #expect(AutoStart.candidate(events: [future, done, plain], now: autoNow, handled: [], isListening: false) == nil)
}

@Test("With two live calls, the one that started first wins")
func autoEarliestStartWins() {
    let later = autoEvent(id: "later", startOffset: -60, location: "https://meet.google.com/aaa-bbbb-ccc")
    let earlier = autoEvent(id: "earlier", startOffset: -900, location: "https://zoom.us/j/3")
    let picked = AutoStart.candidate(events: [later, earlier], now: autoNow, handled: [], isListening: false)
    #expect(picked?.id == "earlier")
}
