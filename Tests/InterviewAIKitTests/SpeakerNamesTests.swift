import Foundation
import Testing
@testable import InterviewAIKit

/// Speaker naming: where names may come from, how they are applied,
/// and the hard rule that the model can only pick from the invited
/// list. Plus the answer layout proportions and the three meeting
/// import parsers.
struct SpeakerNamesTests {

    // MARK: Candidates

    @Test("Candidates are cleaned, deduped, and never the user or an email")
    func candidatesCleaned() {
        let list = SpeakerNames.candidates(
            attendees: [" Jan Sawallisch ", "jan sawallisch", "boss@example.com", "", "Nils Effmert"],
            organizer: "Sharin Sörgel",
            myName: "Nils Effmert"
        )
        #expect(list == ["Jan Sawallisch", "Sharin Sörgel"])
    }

    @Test("The user's own first name alone is also the user")
    func candidatesDropOwnFirstName() {
        #expect(SpeakerNames.candidates(attendees: ["Nils", "Alan Bacior"], myName: "Nils Effmert") == ["Alan Bacior"])
    }

    @Test("Single other only when exactly one candidate remains")
    func singleOther() {
        #expect(SpeakerNames.singleOther(attendees: ["Jan Sawallisch", "Nils Effmert"], myName: "Nils Effmert") == "Jan Sawallisch")
        #expect(SpeakerNames.singleOther(attendees: ["Jan Sawallisch", "Sharin Sörgel"]) == nil)
        #expect(SpeakerNames.singleOther(attendees: []) == nil)
        #expect(SpeakerNames.singleOther(attendees: [], organizer: "Alan Bacior") == "Alan Bacior")
    }

    @Test("First name is the first word")
    func firstName() {
        #expect(SpeakerNames.firstName(of: "Jan Sawallisch") == "Jan")
        #expect(SpeakerNames.firstName(of: "  Alan  ") == "Alan")
        #expect(SpeakerNames.firstName(of: "") == "")
    }

    // MARK: Applying names

    private func segment(_ channel: String, _ label: String?, _ text: String) -> TranscriptSegment {
        TranscriptSegment(channel: channel, text: text, isFinal: true, speakerLabel: label)
    }

    @Test("Applying a mapping renames every surface through the label")
    func applying() {
        let segments = [
            segment("them", nil, "First question."),
            segment("them", "Speaker 1", "Second question."),
            segment("them", "Speaker 2", "A comment."),
            segment("me", nil, "My answer."),
        ]
        let named = SpeakerNames.applying(segments: segments, mapping: [
            "Them": "Sharin Sörgel", "Speaker 1": "Jan Sawallisch", "Speaker 2": "Jan Sawallisch",
        ])
        #expect(named.map(\.speakerName) == ["Sharin Sörgel", "Jan Sawallisch", "Jan Sawallisch", "Me"])
        #expect(TranscriptSegment.plainText(named).hasPrefix("Sharin Sörgel: First question."))
    }

    @Test("Distinct names come back in first-heard order")
    func distinctNames() {
        let segments = [segment("me", nil, "a"), segment("them", "Speaker 2", "b"), segment("them", "Speaker 1", "c"), segment("them", "Speaker 2", "d")]
        #expect(SpeakerNames.distinctNames(segments: segments) == ["Me", "Speaker 2", "Speaker 1"])
    }

    // MARK: The model's mapping, fenced by the candidate list

    @Test("Model mapping keeps only invited names for asked labels")
    func parseMappingValid() {
        let mapping = SpeakerNames.parseMapping(
            "Here is the result: {\"Speaker 1\": \"jan sawallisch\", \"Speaker 2\": \"Sharin Sörgel\"}",
            labels: ["Speaker 1", "Speaker 2"],
            candidates: ["Jan Sawallisch", "Sharin Sörgel"]
        )
        #expect(mapping == ["Speaker 1": "Jan Sawallisch", "Speaker 2": "Sharin Sörgel"])
    }

    @Test("Model mapping drops invented names and unasked labels")
    func parseMappingFenced() {
        let mapping = SpeakerNames.parseMapping(
            "{\"Speaker 1\": \"Domi Rosenberger\", \"Speaker 9\": \"Jan Sawallisch\", \"Speaker 2\": \"Speaker 2\"}",
            labels: ["Speaker 1", "Speaker 2"],
            candidates: ["Jan Sawallisch"]
        )
        #expect(mapping.isEmpty)
        #expect(SpeakerNames.parseMapping("no json at all", labels: ["Speaker 1"], candidates: ["Jan Sawallisch"]).isEmpty)
        #expect(SpeakerNames.parseMapping("{}", labels: ["Speaker 1"], candidates: ["Jan Sawallisch"]).isEmpty)
    }

    // MARK: Answer layout

    @Test("Layout modes carry the split proportions")
    func layoutProportions() {
        #expect(AnswerLayout.balanced.transcriptFraction == 0.5)
        #expect(AnswerLayout.answerFocus.transcriptFraction == 0.32)
        #expect(AnswerLayout.fullWidth.transcriptFraction == 0)
        #expect(AnswerLayout.balanced.showsTranscript)
        #expect(AnswerLayout.answerFocus.showsTranscript)
        #expect(!AnswerLayout.fullWidth.showsTranscript)
        #expect(AnswerLayout(rawValue: "answerFocus") == .answerFocus)
        #expect(AnswerLayout.allCases.map(\.label) == ["Balanced", "Answer Focus", "Full Width"])
    }

    // MARK: Transcript import

    @Test("Pasted transcript keeps speaker names and channels")
    func transcriptImportNames() {
        let parsed = TranscriptImport.parse("""
        Sharin Sörgel: Tell me about your last role.
        Nils Effmert: I led people operations.
        a longer answer that
        runs over two lines.
        Speaker 2: And the budget?
        """, myName: "Nils Effmert")
        #expect(parsed.count == 3)
        #expect(parsed[0].channel == "them")
        #expect(parsed[0].speakerName == "Sharin Sörgel")
        #expect(parsed[1].channel == "me")
        #expect(parsed[1].speakerName == "Nils")
        #expect(parsed[1].text == "I led people operations. a longer answer that runs over two lines.")
        #expect(parsed[2].speakerName == "Speaker 2")
    }

    @Test("Pasted transcript reads bold names and timestamps")
    func transcriptImportFormats() {
        let parsed = TranscriptImport.parse("""
        Just a note with no speaker at all.
        [00:12] **Alan:** How is the training going?
        1:02:03 Me: Better this week.
        """, myName: "")
        #expect(parsed.count == 3)
        #expect(parsed[0].channel == "them")
        #expect(parsed[0].speakerLabel == nil)
        #expect(parsed[1].speakerName == "Alan")
        #expect(parsed[1].startOffset == 12)
        #expect(parsed[2].channel == "me")
        #expect(parsed[2].startOffset == 3723)
    }

    @Test("Timestamps parse as minutes or hours")
    func timestampParsing() {
        #expect(TranscriptImport.parseTimestamp("12:34") == 754)
        #expect(TranscriptImport.parseTimestamp("1:02:03") == 3723)
        #expect(TranscriptImport.parseTimestamp("ab:cd") == nil)
        #expect(TranscriptImport.parseTimestamp("12") == nil)
        #expect(TranscriptImport.parseTimestamp("1:2:3:4") == nil)
    }

    // MARK: Link import

    @Test("Links classify into file, YouTube, or refused")
    func classifyLinks() {
        #expect(ImportSource.classify("https://example.com/call.mp3").kind == .directMedia)
        #expect(ImportSource.classify("https://example.com/movie.MP4").kind == .directMedia)
        #expect(ImportSource.classify("https://www.youtube.com/watch?v=abc123&t=4").kind == .youTube(videoID: "abc123"))
        #expect(ImportSource.classify("https://youtu.be/xyz-987").kind == .youTube(videoID: "xyz-987"))
        #expect(ImportSource.classify("https://www.youtube.com/shorts/shot42").kind == .youTube(videoID: "shot42"))
        #expect(ImportSource.classify("https://vimeo.com/12345").kind == .unsupported)
        #expect(ImportSource.classify("not a link").kind == .unsupported)
        #expect(ImportSource.classify("ftp://example.com/call.mp3").kind == .unsupported)
    }

    @Test("YouTube captions become timed segments, music markers dropped")
    func captionParsing() {
        let json = """
        {"events":[
          {"tStartMs": 0, "dDurationMs": 2000, "segs":[{"utf8":"Hello and"}]},
          {"tStartMs": 2000, "dDurationMs": 1000, "segs":[{"utf8":"[Music]"}]},
          {"tStartMs": 3000, "dDurationMs": 2500, "segs":[{"utf8":"welcome back\\n"}]}
        ]}
        """
        let segments = CaptionSegments.parse(json3: Data(json.utf8))
        #expect(segments.count == 2)
        #expect(segments[0].text == "Hello and")
        #expect(segments[0].startOffset == 0)
        #expect(segments[1].text == "welcome back")
        #expect(segments[1].startOffset == 3)
        #expect(segments[1].duration == 2.5)
        #expect(CaptionSegments.parse(json3: Data("junk".utf8)).isEmpty)
    }

    // MARK: File transcription cutting

    @Test("Sentences split on end marks and keep the tail")
    func sentenceSplitting() {
        #expect(SegmentSplitter.sentences("One. Two? Three! Tail without end") == ["One.", "Two?", "Three!", "Tail without end"])
        #expect(SegmentSplitter.sentences("").isEmpty)
    }

    @Test("Chunk segments spread timing in proportion to length")
    func chunkSegments() {
        let segments = SegmentSplitter.segments(text: "Short. A much longer sentence here.", chunkStart: 60, chunkDuration: 10)
        #expect(segments.count == 2)
        #expect(segments[0].startOffset == 60)
        #expect((segments[0].duration ?? 0) < (segments[1].duration ?? 0))
        let total = segments.compactMap(\.duration).reduce(0, +)
        #expect(abs(total - 10) < 0.001)
        #expect(segments.allSatisfy { $0.channel == "them" && $0.isFinal })
    }
}
