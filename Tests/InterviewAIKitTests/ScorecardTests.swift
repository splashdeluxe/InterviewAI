import Foundation
import Testing
@testable import InterviewAIKit

@Test("A full scorecard reply parses into its sections and verdict")
func scorecardParses() {
    let raw = #"""
        {"probed": [{"t": "Pressed on planning depth twice", "at": 305}],
         "evidence": [{"t": "Gave the thermondo planning rebuild with numbers", "at": 512}],
         "gaps": [{"t": "Stayed vague on forecasting method", "at": 640}],
         "verdict": "Strong operator, forecasting depth unproven."}
        """#
    let card = ScorecardParsing.parse(raw, maxSeconds: 900)
    #expect(card?.probed.count == 1)
    #expect(card?.probed.first?.atSeconds == 305)
    #expect(card?.evidence.first?.text.contains("thermondo") == true)
    #expect(card?.gaps.count == 1)
    #expect(card?.verdict == "Strong operator, forecasting depth unproven.")
}

@Test("A point resting on a moment outside the call is dropped")
func scorecardDropsOutOfRangePoint() {
    let raw = #"""
        {"probed": [{"t": "Asked about notice period", "at": 60},
                     {"t": "Point from a moment that never happened", "at": 5000}],
         "evidence": [], "gaps": [], "verdict": ""}
        """#
    let card = ScorecardParsing.parse(raw, maxSeconds: 900)
    #expect(card?.probed.count == 1)
    #expect(card?.probed.first?.text == "Asked about notice period")
}

@Test("Duplicate points collapse, fragments are dropped")
func scorecardDedupesAndDropsFragments() {
    let raw = #"""
        {"probed": [{"t": "Pressed on salary expectations early", "at": 100},
                     {"t": "Pressed on salary expectations early!", "at": 104},
                     {"t": "Short", "at": 120}],
         "evidence": [], "gaps": [], "verdict": ""}
        """#
    let card = ScorecardParsing.parse(raw, maxSeconds: 900)
    #expect(card?.probed.count == 1)
}

@Test("A fenced reply still parses, a missing section is empty")
func scorecardParsesFencedWithMissingSection() {
    let raw = """
        Here is the scorecard:
        ```json
        {"evidence": [{"t": "Named three shipped automations unprompted", "at": 42}], "verdict": "Prepared."}
        ```
        """
    let card = ScorecardParsing.parse(raw, maxSeconds: 900)
    #expect(card?.probed.isEmpty == true)
    #expect(card?.evidence.count == 1)
    #expect(card?.verdict == "Prepared.")
}

@Test("Prose without JSON is no scorecard, an empty reply is an empty card")
func scorecardRejectsProse() {
    #expect(ScorecardParsing.parse("The candidate did well overall.", maxSeconds: 900) == nil)
    let empty = ScorecardParsing.parse("{\"probed\": [], \"evidence\": [], \"gaps\": [], \"verdict\": \"\"}", maxSeconds: 900)
    #expect(empty?.isEmpty == true)
}

@Test("A scorecard round-trips through its stored JSON")
func scorecardRoundTrips() {
    let card = InterviewScorecard(
        probed: [ScorecardPoint(text: "Pressed on planning depth twice", atSeconds: 305)],
        evidence: [],
        gaps: [ScorecardPoint(text: "Stayed vague on forecasting method", atSeconds: 640)],
        verdict: "Strong operator."
    )
    let decoded = InterviewScorecard.decode(InterviewScorecard.encode(card))
    #expect(decoded == card)
    #expect(InterviewScorecard.decode("") == nil)
}

@Test("The scorecard prompts carry the no-invention and language rules")
func scorecardPromptGuardrails() {
    #expect(ScorecardPrompts.system.contains("Never invent"))
    #expect(ScorecardPrompts.system.contains("language the conversation was held in"))
    #expect(ScorecardPrompts.system.contains("[seconds]"))
    #expect(ScorecardMergePrompts.system.contains("never invent"))
}
