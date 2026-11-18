import Foundation
import Testing
@testable import InterviewAIKit

/// Transcript tools from the Hedy transcript round: timestamp
/// labels and exports, the diarization outcome notes, and the
/// Clean Transcript prompts and output parsing.
struct TranscriptToolsTests {

    // MARK: Timestamps

    @Test("Timestamp labels are m:ss under an hour and h:mm:ss past it")
    func timestampLabels() {
        #expect(TranscriptTime.label(seconds: 0) == "0:00")
        #expect(TranscriptTime.label(seconds: 7) == "0:07")
        #expect(TranscriptTime.label(seconds: 65) == "1:05")
        #expect(TranscriptTime.label(seconds: 754) == "12:34")
        #expect(TranscriptTime.label(seconds: 3661) == "1:01:01")
        #expect(TranscriptTime.label(seconds: -5) == "0:00")
    }

    @Test("Plain text carries timestamps only when asked and only when known")
    func plainTextTimestamps() {
        let segments = [
            TranscriptSegment(channel: "them", text: "Hello there.", isFinal: true, speakerLabel: "Alan", startOffset: 754),
            TranscriptSegment(channel: "me", text: "Hi Alan.", isFinal: true, speakerLabel: "Nils"),
        ]
        #expect(TranscriptSegment.plainText(segments) == "Alan: Hello there.\nNils: Hi Alan.")
        #expect(TranscriptSegment.plainText(segments, includeTimestamps: true)
            == "[12:34] Alan: Hello there.\nNils: Hi Alan.")
    }

    @Test("Exports carry timestamps only when asked")
    func exportTimestamps() {
        let segments = [
            TranscriptSegment(channel: "them", text: "Hello there.", isFinal: true, speakerLabel: "Alan", startOffset: 65),
        ]
        let plain = TranscriptExport.markdown(title: "T", date: Date(timeIntervalSince1970: 0), attendees: [], location: "", segments: segments, summary: "")
        #expect(!plain.contains("[1:05]"))
        let stamped = TranscriptExport.markdown(title: "T", date: Date(timeIntervalSince1970: 0), attendees: [], location: "", segments: segments, summary: "", includeTimestamps: true)
        #expect(stamped.contains("[1:05] **Alan:** Hello there."))
        let text = TranscriptExport.plainText(title: "T", date: Date(timeIntervalSince1970: 0), attendees: [], location: "", segments: segments, summary: "", includeTimestamps: true)
        #expect(text.contains("[1:05] Alan: Hello there."))
    }

    // MARK: Diarization notes

    @Test("Diarization notes are plain and distinct")
    func diarizationNotes() {
        #expect(DiarizationNotes.tooShort.contains("too short"))
        #expect(DiarizationNotes.unavailable.hasPrefix("Speaker labels are unavailable"))
        #expect(DiarizationNotes.firstHourOnly.contains("first hour"))
        #expect(Set([DiarizationNotes.tooShort, DiarizationNotes.unavailable, DiarizationNotes.firstHourOnly]).count == 3)
    }

    // MARK: Clean Transcript

    @Test("Clean prompt carries the confirmed names and the summary")
    func cleanPromptContext() {
        let user = CleanTranscriptPrompts.user(
            confirmedNames: ["Alan", "Nils"], attendees: ["Alan Bacior"],
            summary: "A coaching call with Alan Bacior about training.",
            transcript: "Speaker 1: Hello."
        )
        #expect(user.contains("Confirmed speakers: Alan, Nils"))
        #expect(user.contains("Invited: Alan Bacior"))
        #expect(user.contains("coaching call with Alan Bacior"))
        #expect(user.contains("Speaker 1: Hello."))
        #expect(CleanTranscriptPrompts.system.contains("never summarize"))
    }

    @Test("Cleaned output parses back to named segments, markers and fences dropped")
    func cleanedParsing() {
        let raw = """
        ```text
        Alan: Thanks for joining today.
        [Music]
        Nils: Happy to be here, the plan is working.
        Alan: [Applause]
        Speaker 2: One more thing to check.
        ```
        """
        let segments = CleanedTranscript.segments(from: raw, myName: "Nils Effmert")
        #expect(segments.count == 3)
        #expect(segments[0].speakerName == "Alan")
        #expect(segments[0].channel == "them")
        #expect(segments[1].speakerName == "Nils")
        #expect(segments[1].channel == "me")
        #expect(segments[2].speakerName == "Speaker 2")
        #expect(segments.allSatisfy { !$0.text.contains("[Music]") && !$0.text.contains("[Applause]") })
    }
}
