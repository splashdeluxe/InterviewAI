import Foundation
import Testing
@testable import InterviewAIKit

/// The suggestion engine's gates, parsing, and dedupe. The model
/// calls live in the app; everything decided here is pure.
struct SuggestionsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Engine stays off, warms up, and needs real material")
    func gateBasics() {
        let later = start.addingTimeInterval(300)
        #expect(!SuggestionEngine.shouldEvaluate(now: later, sessionStartedAt: start, lastCycleAt: nil, frequency: .off, themSegmentCount: 9))
        #expect(!SuggestionEngine.shouldEvaluate(now: start.addingTimeInterval(60), sessionStartedAt: start, lastCycleAt: nil, frequency: .balanced, themSegmentCount: 9))
        #expect(!SuggestionEngine.shouldEvaluate(now: later, sessionStartedAt: start, lastCycleAt: nil, frequency: .balanced, themSegmentCount: 2))
        #expect(SuggestionEngine.shouldEvaluate(now: later, sessionStartedAt: start, lastCycleAt: nil, frequency: .balanced, themSegmentCount: 3))
    }

    @Test("Engine respects the cadence per frequency")
    func gateCadence() {
        let cycle = start.addingTimeInterval(200)
        // 100 seconds after a cycle: too soon for balanced (150), fine for nothing else.
        #expect(!SuggestionEngine.shouldEvaluate(now: cycle.addingTimeInterval(100), sessionStartedAt: start, lastCycleAt: cycle, frequency: .balanced, themSegmentCount: 5))
        // 200 seconds after: balanced and frequent may run, selective (240) may not.
        #expect(SuggestionEngine.shouldEvaluate(now: cycle.addingTimeInterval(200), sessionStartedAt: start, lastCycleAt: cycle, frequency: .balanced, themSegmentCount: 5))
        #expect(!SuggestionEngine.shouldEvaluate(now: cycle.addingTimeInterval(200), sessionStartedAt: start, lastCycleAt: cycle, frequency: .selective, themSegmentCount: 5))
        #expect(SuggestionEngine.shouldEvaluate(now: cycle.addingTimeInterval(260), sessionStartedAt: start, lastCycleAt: cycle, frequency: .selective, themSegmentCount: 5))
    }

    @Test("Candidates parse from clean JSON lines")
    func parsesClean() {
        let raw = """
        {"kind": "ask", "text": "Ask what success looks like in six months.", "why": "It pins the role down."}
        {"kind": "follow-up", "text": "Ask who else signs off on the budget.", "why": "He mentioned approval twice."}
        """
        let parsed = SuggestionEngine.parseCandidates(raw)
        #expect(parsed.count == 2)
        #expect(parsed.first?.kind == .ask)
        #expect(parsed.last?.kind == .followUp)
        #expect(parsed.first?.why == "It pins the role down.")
    }

    @Test("Candidates parse out of fences and prose, junk is dropped")
    func parsesMessy() {
        let raw = """
        Here are some ideas:
        ```json
        {"kind": "missed", "text": "She named a start date and nobody picked it up.", "why": "Dates drive the offer."}
        {"kind": "nonsense", "text": "Dropped, unknown kind.", "why": "x"}
        {"kind": "framing", "text": "", "why": "Dropped, empty."}
        ```
        Hope that helps.
        """
        let parsed = SuggestionEngine.parseCandidates(raw)
        #expect(parsed.count == 1)
        #expect(parsed.first?.kind == .missedDetail)
        #expect(SuggestionEngine.parseCandidates("NONE").isEmpty)
        #expect(SuggestionEngine.parseCandidates("no json here").isEmpty)
    }

    @Test("The filter pick lands on a candidate or on none")
    func pickParsing() {
        let candidates = [
            Suggestion(kind: .ask, text: "One", why: "a"),
            Suggestion(kind: .framing, text: "Two", why: "b"),
        ]
        #expect(SuggestionEngine.parsePick("PICK 2", candidates: candidates)?.text == "Two")
        #expect(SuggestionEngine.parsePick("pick 1", candidates: candidates)?.text == "One")
        #expect(SuggestionEngine.parsePick("NONE", candidates: candidates) == nil)
        #expect(SuggestionEngine.parsePick("PICK 5", candidates: candidates) == nil)
        #expect(SuggestionEngine.parsePick("The second one is best", candidates: candidates) == nil)
    }

    @Test("A near-repeat of a given tip is a duplicate, a fresh angle is not")
    func dedupe() {
        let previous = ["Ask what success looks like in six months."]
        #expect(SuggestionEngine.isDuplicate("Ask what success looks like in the first six months.", previous: previous))
        #expect(!SuggestionEngine.isDuplicate("Ask who else signs off on the budget.", previous: previous))
        #expect(!SuggestionEngine.isDuplicate("Ask what success looks like in six months.", previous: []))
    }

    @Test("Suggestions round-trip through the meeting JSON")
    func roundTrip() {
        let tips = [Suggestion(kind: .missedDetail, text: "She named a start date.", why: "Dates drive the offer.")]
        #expect(Suggestion.decode(Suggestion.encode(tips)) == tips)
        #expect(Suggestion.decode("").isEmpty)
        #expect(Suggestion.decode("not json").isEmpty)
    }

    @Test("The draft prompt carries the session context when setup gave one")
    func draftCarriesContext() {
        let withContext = SuggestionPrompts.draftUser(modeName: "General", transcript: "Them: Hi", previousTips: [], context: "Call with Alan, my coach")
        #expect(withContext.contains("Session context: Call with Alan, my coach"))
        let without = SuggestionPrompts.draftUser(modeName: "General", transcript: "Them: Hi", previousTips: [])
        #expect(!without.contains("Session context:"))
    }
}
