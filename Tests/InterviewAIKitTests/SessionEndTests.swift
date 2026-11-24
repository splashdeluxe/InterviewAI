import Foundation
import Testing
@testable import InterviewAIKit

private func seg(_ text: String, channel: String = "me") -> TranscriptSegment {
    TranscriptSegment(channel: channel, text: text, isFinal: true)
}

@Test("Word count sums every line on both channels")
func sessionEndWordCountSums() {
    let segments = [seg("Hello there", channel: "them"), seg("Hi, how are you?")]
    #expect(SessionEnd.wordCount(segments) == 6)
}

@Test("Word count ignores stray whitespace and empty lines")
func sessionEndWordCountWhitespace() {
    let segments = [seg("  spaced   out  "), seg(""), seg("   ")]
    #expect(SessionEnd.wordCount(segments) == 2)
    #expect(SessionEnd.wordCount([]) == 0)
}

@Test("Only a few words prompt; none and enough do not")
func sessionEndMistakeBoundaries() {
    #expect(!SessionEnd.looksLikeMistake(wordCount: 0))
    #expect(SessionEnd.looksLikeMistake(wordCount: 1))
    #expect(SessionEnd.looksLikeMistake(wordCount: SessionEnd.mistakeWordLimit - 1))
    #expect(!SessionEnd.looksLikeMistake(wordCount: SessionEnd.mistakeWordLimit))
    #expect(!SessionEnd.looksLikeMistake(wordCount: 200))
}
