import XCTest
@testable import InterviewAIKit

final class SpeakerConfirmationTests: XCTestCase {
    private func segment(channel: String = "them", label: String? = nil,
                         text: String, offset: Double? = nil,
                         isFinal: Bool = true) -> TranscriptSegment {
        TranscriptSegment(channel: channel, text: text, isFinal: isFinal,
                          speakerLabel: label, startOffset: offset)
    }

    func testVoicesGroupByLabelInFirstHeardOrder() {
        let segments = [
            segment(label: "Alex", text: "Hello there.", offset: 1.0),
            segment(label: "Speaker 2", text: "Let us start.", offset: 9.5),
            segment(label: "Alex", text: "Tell me more.", offset: 20.0),
            segment(text: "Untracked line.", offset: 30.0),
        ]
        // Only the voices diarization found are speakers. The
        // untracked line is not a third voice; it is reported
        // separately as unassigned.
        let voices = SpeakerConfirmation.voices(in: segments)
        XCTAssertEqual(voices.map(\.name), ["Alex", "Speaker 2"])
        XCTAssertEqual(voices.map(\.lineCount), [2, 1])
        XCTAssertEqual(voices[0].sample, "Hello there.")
        XCTAssertEqual(voices[0].firstOffset, 1.0)
        XCTAssertEqual(voices[1].firstOffset, 9.5)
        let loose = SpeakerConfirmation.unassigned(in: segments)
        XCTAssertEqual(loose?.lineCount, 1)
        XCTAssertEqual(loose?.sample, "Untracked line.")
        XCTAssertEqual(loose?.firstOffset, 30.0)
    }

    func testVoicesSkipOwnLinesAndNonFinalLines() {
        let segments = [
            segment(channel: "me", text: "My own line.", offset: 0.0),
            segment(label: "Alex", text: "Draft line.", offset: 1.0, isFinal: false),
            segment(label: "Alex", text: "Real line.", offset: 2.0),
        ]
        let voices = SpeakerConfirmation.voices(in: segments)
        XCTAssertEqual(voices.count, 1)
        XCTAssertEqual(voices[0].lineCount, 1)
        XCTAssertEqual(voices[0].sample, "Real line.")
        XCTAssertEqual(voices[0].firstOffset, 2.0)
    }

    func testIsGeneric() {
        XCTAssertTrue(SpeakerConfirmation.isGeneric("Them"))
        XCTAssertTrue(SpeakerConfirmation.isGeneric("Speaker 1"))
        XCTAssertTrue(SpeakerConfirmation.isGeneric("Speaker 12"))
        XCTAssertFalse(SpeakerConfirmation.isGeneric("Alex"))
        XCTAssertFalse(SpeakerConfirmation.isGeneric("Speaker"))
        XCTAssertFalse(SpeakerConfirmation.isGeneric("Speaker One"))
        XCTAssertFalse(SpeakerConfirmation.isGeneric("Me"))
    }

    func testNeedsConfirmation() {
        // Nobody on the other side: nothing to confirm.
        XCTAssertFalse(SpeakerConfirmation.needsConfirmation(segments: [
            segment(channel: "me", text: "Only me."),
        ]))
        // One voice, already a real name: fine as it stands.
        XCTAssertFalse(SpeakerConfirmation.needsConfirmation(segments: [
            segment(label: "Alan", text: "Hi."),
        ]))
        // A named voice plus lines no voice claimed: ask, the
        // loose lines need an owner.
        XCTAssertTrue(SpeakerConfirmation.needsConfirmation(segments: [
            segment(label: "Alan", text: "Hi."),
            segment(text: "Whose line is this?"),
        ]))
        // No voice at all, only unclaimed lines: ask.
        XCTAssertTrue(SpeakerConfirmation.needsConfirmation(segments: [
            segment(text: "Hi."),
        ]))
        // One person split across two labels: ask.
        XCTAssertTrue(SpeakerConfirmation.needsConfirmation(segments: [
            segment(label: "Alex", text: "Hi."),
            segment(label: "Speaker 2", text: "Also me."),
        ]))
        // Two numbered voices: ask.
        XCTAssertTrue(SpeakerConfirmation.needsConfirmation(segments: [
            segment(label: "Speaker 1", text: "Hi."),
            segment(label: "Speaker 2", text: "Hello."),
        ]))
    }

    func testOnePersonFixIsAPlainRename() {
        // The thermondo shape: one person under two labels plus an
        // unnamed tail. The sheet's one-person answer maps every
        // voice to the one name and adds the unassigned lines under
        // their "Them" key, so one rename pass fixes all of it.
        let segments = [
            segment(label: "Alex", text: "One."),
            segment(label: "Speaker 2", text: "Two."),
            segment(text: "Three."),
        ]
        var mapping = Dictionary(uniqueKeysWithValues:
            SpeakerConfirmation.voices(in: segments).map { ($0.name, "Alex") })
        if SpeakerConfirmation.unassigned(in: segments) != nil {
            mapping["Them"] = "Alex"
        }
        let fixed = SpeakerNames.applying(segments: segments, mapping: mapping)
        XCTAssertEqual(fixed.map(\.speakerName), ["Alex", "Alex", "Alex"])
        XCTAssertEqual(SpeakerConfirmation.voices(in: fixed).map(\.name), ["Alex"])
        XCTAssertNil(SpeakerConfirmation.unassigned(in: fixed))
        XCTAssertFalse(SpeakerConfirmation.needsConfirmation(segments: fixed))
    }
}
