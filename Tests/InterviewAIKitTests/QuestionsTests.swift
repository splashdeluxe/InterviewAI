import Foundation
import Testing
@testable import InterviewAIKit

private func segment(_ channel: String, _ text: String, offset: Double, label: String? = nil) -> TranscriptSegment {
    TranscriptSegment(channel: channel, text: text, isFinal: true, speakerLabel: label, startOffset: offset)
}

@Test("A quoted question and answer fence into a pair with the line's name and time")
func questionPairFences() {
    let segments = [
        segment("them", "What is your salary expectation for this role?", offset: 100, label: "Alex"),
        segment("me", "I asked for 95,000 and the band starts at 75,000.", offset: 112),
        segment("them", "That works for us.", offset: 130, label: "Alex"),
    ]
    let raw = #"[{"q": "What is your salary expectation for this role?", "a": "I asked for 95,000 and the band starts at 75,000."}]"#
    let pairs = QuestionExtraction.pairs(from: raw, segments: segments)
    #expect(pairs.count == 1)
    #expect(pairs.first?.asker == "Alex")
    #expect(pairs.first?.atSeconds == 100)
    #expect(pairs.first?.answer == "I asked for 95,000 and the band starts at 75,000.")
}

@Test("An answer the user never gave is dropped, the question stays")
func inventedAnswerDropped() {
    let segments = [
        segment("them", "When could you start?", offset: 40, label: "Alex"),
        segment("me", "Let me think about the notice period first.", offset: 52),
    ]
    let raw = #"[{"q": "When could you start?", "a": "I can start on Monday morning right away."}]"#
    let pairs = QuestionExtraction.pairs(from: raw, segments: segments)
    #expect(pairs.count == 1)
    #expect(pairs.first?.answer == "")
}

@Test("A question that is not in the transcript is dropped")
func inventedQuestionDropped() {
    let segments = [
        segment("them", "Tell me about your last role.", offset: 10, label: "Alex"),
        segment("me", "I led People Operations for five years.", offset: 24),
    ]
    let raw = #"[{"q": "What is your greatest weakness?", "a": "I led People Operations for five years."}]"#
    #expect(QuestionExtraction.pairs(from: raw, segments: segments).isEmpty)
}

@Test("A question spread over two lines still fences")
func multiLineQuestionFences() {
    let segments = [
        segment("them", "So it is not about me today, it is about you.", offset: 60, label: "Alex"),
        segment("them", "Give me a short intro, why are you looking right now?", offset: 74, label: "Alex"),
        segment("me", "Thanks for having me, glad to be here.", offset: 90),
    ]
    let raw = #"[{"q": "So it is not about me today, it is about you. Give me a short intro, why are you looking right now?", "a": "Thanks for having me, glad to be here."}]"#
    let pairs = QuestionExtraction.pairs(from: raw, segments: segments)
    #expect(pairs.count == 1)
    #expect(pairs.first?.atSeconds == 60)
    #expect(pairs.first?.answer == "Thanks for having me, glad to be here.")
}

@Test("Short quotes and prose around the JSON are handled")
func shortQuoteAndProse() {
    let segments = [
        segment("them", "Yeah?", offset: 5, label: "Alex"),
        segment("me", "Yes.", offset: 7),
    ]
    let raw = "Here are the questions:\n[{\"q\": \"Yeah?\", \"a\": \"Yes.\"}]\nDone."
    #expect(QuestionExtraction.pairs(from: raw, segments: segments).isEmpty)
}

@Test("Question pairs round trip through their store JSON")
func questionPairRoundTrip() {
    let pairs = [QuestionPair(question: "Why us?", asker: "Alex", answer: "Because of the planning team.", atSeconds: 42)]
    #expect(QuestionPair.decode(QuestionPair.encode(pairs)) == pairs)
    #expect(QuestionPair.decode("").isEmpty)
}

@Test("The extraction prompt asks for word-for-word JSON quotes")
func questionPromptShape() {
    #expect(QuestionPrompts.system.contains("JSON array only"))
    #expect(QuestionPrompts.system.contains("word for word"))
    #expect(QuestionPrompts.user(transcript: "Me: Hi").contains("Transcript:"))
}
