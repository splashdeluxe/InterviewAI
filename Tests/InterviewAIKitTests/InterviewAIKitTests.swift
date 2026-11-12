import Foundation
import Testing
@testable import InterviewAIKit

@Test("Ranker scores shared words")
func rankerScores() {
    #expect(ContextRanker.score(document: "I led People Operations for a team of forty", query: "people operations team") == 3)
    #expect(ContextRanker.score(document: "Cooking recipes and travel notes", query: "people operations team") == 0)
}

@Test("Pinned documents always rank first, zero-score unpinned are dropped")
func rankerPinned() {
    let docs: [(name: String, text: String, pinned: Bool)] = [
        (name: "resume.md", text: "unrelated words only", pinned: true),
        (name: "notes.md", text: "salary negotiation band", pinned: false),
        (name: "other.md", text: "nothing in common here", pinned: false),
    ]
    let ranked = ContextRanker.rank(documents: docs, query: "salary negotiation")
    #expect(ranked.map(\.name) == ["resume.md", "notes.md"])
}

@Test("Auto answer gate skips back-channels and answers real questions")
func autoAnswerGate() {
    #expect(!AutoAnswerGate.shouldAnswer("Yeah."))
    #expect(!AutoAnswerGate.shouldAnswer("Okay."))
    #expect(!AutoAnswerGate.shouldAnswer("Right, right."))
    #expect(!AutoAnswerGate.shouldAnswer("Mm-hm, sure."))
    #expect(AutoAnswerGate.shouldAnswer("What is your salary expectation?"))
    #expect(AutoAnswerGate.shouldAnswer("Tell me about a People Operations team you built."))
    #expect(AutoAnswerGate.shouldAnswer("How would you handle onboarding for a remote team"))
    #expect(AutoAnswerGate.shouldAnswer("We are looking for someone who has run payroll across three countries before."))
    #expect(!AutoAnswerGate.shouldAnswer("So, yeah, anyway."))
}

@Test("Prompt restates the other side's last line at the instruction")
func promptRestatesQuestion() {
    let segments = [
        TranscriptSegment(channel: "them", text: "What is your salary expectation?", isFinal: true),
    ]
    let user = PromptBuilder.userMessage(
        action: .answer, typedQuestion: nil, customContext: "",
        documents: [], transcript: segments, screenshotNote: false)
    #expect(user.contains("The other side just said: \"What is your salary expectation?\""))
}

@Test("Prompt carries mode rules, pinned context, transcript, and the action")
func promptBuilds() {
    let segments = [
        TranscriptSegment(channel: "them", text: "What is your salary expectation?", isFinal: true),
        TranscriptSegment(channel: "me", text: "Let me think.", isFinal: true),
    ]
    let user = PromptBuilder.userMessage(
        action: .answer, typedQuestion: nil, customContext: "Target band is 95k.",
        documents: [(name: "resume.md", text: "People Operations lead", pinned: true)],
        transcript: segments, screenshotNote: false)
    #expect(user.contains("Target band is 95k."))
    #expect(user.contains("People Operations lead"))
    #expect(user.contains("Them: What is your salary expectation?"))
    #expect(user.contains(AnswerAction.answer.instruction))
    let system = PromptBuilder.systemPrompt(modePrompt: BuiltInModes.mode(id: "looking-for-work").prompt)
    #expect(system.contains("do not invent it"))
}

@Test("Transcript round-trips through JSON and plain text skips partials")
func transcriptCoding() {
    let segments = [
        TranscriptSegment(channel: "them", text: "Hello there", isFinal: true),
        TranscriptSegment(channel: "me", text: "draft", isFinal: false),
    ]
    let back = TranscriptSegment.decode(TranscriptSegment.encode(segments))
    #expect(back == segments)
    #expect(TranscriptSegment.plainText(segments) == "Them: Hello there")
}

@Test("Stream line parsing matches each provider shape")
func streamParsing() {
    #expect(Brain.extract(line: "{\"message\":{\"content\":\"Hi\"}}", kind: .ollama) == "Hi")
    #expect(Brain.extract(line: "data: {\"choices\":[{\"delta\":{\"content\":\"Yo\"}}]}", kind: .openAICompatible) == "Yo")
    #expect(Brain.extract(line: "data: [DONE]", kind: .openAICompatible) == nil)
    #expect(Brain.extract(line: "not json", kind: .ollama) == nil)
}

@Test("Action numbers map to the row order")
func actionNumbers() {
    #expect(AnswerAction.action(forNumber: 1) == .whatToSay)
    #expect(AnswerAction.action(forNumber: 7) == .brainstorm)
    #expect(AnswerAction.action(forNumber: 8) == nil)
}

@Test("Nine built-in modes, looking-for-work present")
func builtInModes() {
    #expect(BuiltInModes.all.count == 9)
    #expect(BuiltInModes.mode(id: "looking-for-work").name == "Looking for Work")
    #expect(BuiltInModes.mode(id: "missing").id == "general")
}

@Test func intelligencePromptsCarryTheDocuments() {
    let profile = IntelligencePrompts.profile(resume: "Nils, People Lead, DATEV")
    #expect(profile.user.contains("## Identity"))
    #expect(profile.user.contains("DATEV"))
    let points = IntelligencePrompts.talkingPoints(resume: "RESUME-TEXT", jobDescription: "JD-TEXT")
    #expect(points.user.contains("RESUME-TEXT"))
    #expect(points.user.contains("JD-TEXT"))
    #expect(points.user.contains("## Gaps, answered honestly"))
    let intel = IntelligencePrompts.companyIntel(company: "KNIME", jobDescription: "", webResults: [SearchResult(title: "T", url: "https://example.com", snippet: "S")])
    #expect(intel.user.contains("KNIME"))
    #expect(intel.user.contains("https://example.com"))
    let letter = IntelligencePrompts.coverLetter(resume: "RESUME-TEXT", jobDescription: "JD-TEXT")
    #expect(letter.system.contains("first person"))
}

@Test func tavilyResponseParses() {
    let json = #"{"results":[{"title":"A","url":"https://a.example","content":"snippet a"},{"title":"B","url":"https://b.example","content":"snippet b"}]}"#
    let results = WebSearch.parseTavily(data: Data(json.utf8))
    #expect(results.count == 2)
    #expect(results.first?.title == "A")
    #expect(WebSearch.parseTavily(data: Data("nope".utf8)).isEmpty)
}

@Test func chunkPolicyCutsOnAPause() {
    var policy = ChunkPolicy()
    let halfSecond = ChunkPolicy.sampleRate / 2
    // Four seconds of speech: no cut yet, however it is fed.
    for _ in 0..<8 {
        #expect(policy.feed(blockSamples: halfSecond, rms: 0.05) == false)
    }
    #expect(policy.hasSpeech)
    // Short pauses do not cut; a 1 second pause does.
    #expect(policy.feed(blockSamples: halfSecond, rms: 0.001) == false)
    #expect(policy.feed(blockSamples: halfSecond, rms: 0.001) == true)
    policy.reset()
    #expect(policy.bufferedSamples == 0)
    #expect(policy.hasSpeech == false)
}

@Test func chunkPolicyCutsSoonerOnAShortPause() {
    var policy = ChunkPolicy()
    let halfSecond = ChunkPolicy.sampleRate / 2
    // Three seconds of speech: no cut while words are still coming.
    for _ in 0..<6 {
        #expect(policy.feed(blockSamples: halfSecond, rms: 0.05) == false)
    }
    // A half-second pause is a breath, not an ending; a full second cuts.
    #expect(policy.feed(blockSamples: halfSecond, rms: 0.001) == false)
    #expect(policy.feed(blockSamples: halfSecond, rms: 0.001) == true)
}

@Test func chunkPolicyHardCapAndSilence() {
    var policy = ChunkPolicy()
    let halfSecond = ChunkPolicy.sampleRate / 2
    // Continuous speech is cut at the 15 second cap.
    var cutAt: Int?
    for step in 1...30 {
        if policy.feed(blockSamples: halfSecond, rms: 0.05), cutAt == nil { cutAt = step }
    }
    #expect(cutAt == 30)

    // Pure silence also hits the cap, but hasSpeech stays false, so the
    // channel drops the chunk instead of transcribing it.
    var quiet = ChunkPolicy()
    var quietCut = false
    for _ in 1...30 { quietCut = quiet.feed(blockSamples: halfSecond, rms: 0.001) || quietCut }
    #expect(quietCut)
    #expect(quiet.hasSpeech == false)
}

@Test func translationPromptNamesTheTargetAndStaysBare() {
    let system = TranslationPrompts.system(target: "English")
    #expect(system.contains("English"))
    #expect(system.contains("only the translation"))
    #expect(TranslationPrompts.languages.contains("German"))
    #expect(TranslationPrompts.languages.contains("Indonesian"))
}

@Test func segmentOptionalFieldsRoundtripAndLegacyDecode() {
    // Segments saved before translation and speakers existed carry none
    // of the new fields; they must still decode.
    let legacy = #"[{"id":"3E9C6F3A-1A2B-4C3D-8E4F-5A6B7C8D9E0F","channel":"them","text":"Hallo zusammen.","at":763000000,"isFinal":true}]"#
    let decoded = TranscriptSegment.decode(legacy)
    #expect(decoded.count == 1)
    #expect(decoded.first?.translatedText == nil)
    #expect(decoded.first?.speakerName == "Them")
    #expect(decoded.first?.displayText == "Hallo zusammen.")

    var segment = TranscriptSegment(channel: "them", text: "Hallo zusammen.", isFinal: true)
    segment.translatedText = "Hello everyone."
    segment.speakerLabel = "Speaker 2"
    let roundtrip = TranscriptSegment.decode(TranscriptSegment.encode([segment]))
    #expect(roundtrip.first?.displayText == "Hello everyone.")
    #expect(roundtrip.first?.speakerName == "Speaker 2")
    // The original wording is untouched for prompts and summaries.
    #expect(TranscriptSegment.plainText(roundtrip).contains("Hallo zusammen."))
}

@Test func speakerAssignerLabelsByOverlapInFirstHeardOrder() {
    let ranges = [
        SpeakerAssigner.Range(speaker: "b", start: 10, end: 20),
        SpeakerAssigner.Range(speaker: "a", start: 0, end: 10),
        SpeakerAssigner.Range(speaker: "b", start: 20, end: 26),
    ]
    let windows: [(start: Double, end: Double)?] = [
        (start: 1, end: 5),    // a, heard first
        (start: 11, end: 15),  // b
        (start: 21, end: 24),  // b again, same number
        nil,                   // no timing: no label
        (start: 40, end: 44),  // nobody overlaps: no label
    ]
    let labels = SpeakerAssigner.labels(windows: windows, ranges: ranges)
    #expect(labels == ["Speaker 1", "Speaker 2", "Speaker 2", nil, nil])
}

@Test func contextClassifierTrustsTheNameFirst() {
    #expect(ContextClassifier.kind(forName: "resume-2026.pdf") == "resume")
    #expect(ContextClassifier.kind(forName: "Lebenslauf.pdf") == "resume")
    #expect(ContextClassifier.kind(forName: "Senior Lead JD.pdf") == "job")
    #expect(ContextClassifier.kind(forName: "meeting-notes.md") == "notes")
    #expect(ContextClassifier.kind(forName: "random.pdf") == "general")
}

@Test func contextClassifierReadsTheTextWhenTheNameSaysNothing() {
    // A resume named after its owner: the name carries no hint at all.
    let cv = """
    Nils Effmert. People Operations lead. Work Experience: Head of People \
    Operations, DATEV product owner. Education: degree in business. \
    Skills: HR systems, automation, payroll. Languages: German, English. \
    Certifications: Scrum. Professional summary: fifteen years in HR.
    """
    #expect(ContextClassifier.kind(forName: "Nils_Effmert.pdf", text: cv) == "resume")
    let jd = """
    About the role: we are looking for a Head of People Operations. \
    Responsibilities: own the people roadmap. Requirements: eight years \
    in HR leadership. Qualifications: systems thinker. Benefits: remote. \
    We are an equal opportunity employer.
    """
    #expect(ContextClassifier.kind(forName: "opening.pdf", text: jd) == "job")
    // A prep pack quotes both sides; no clear winner, so it stays general.
    let pack = """
    Interview prep pack. My work experience and education in short, the \
    role's responsibilities and requirements in short, my skills matched \
    against their qualifications, plus likely questions, honest answers, \
    and a checklist of things to ask them about the team and the roadmap.
    """
    #expect(ContextClassifier.kind(forName: "interview-prep-pack.md", text: pack) == "general")
    // Too little text to judge stays general.
    #expect(ContextClassifier.kind(forName: "x.pdf", text: "Education and skills.") == "general")
}

@Test func summaryCleanerStripsEchoedScaffolding() {
    // The exact failure seen in real use: the model parrots the old
    // prompt's shape labels instead of writing a summary.
    #expect(SummaryCleaner.clean("### Shape: Summary: Summary: Summary: Decision: Action item:") == "")
    #expect(SummaryCleaner.clean("Summary: Summary:\nWe agreed to ship on Friday.\nDecisions:\n- Ship Friday") == "We agreed to ship on Friday.\nDecisions:\n- Ship Friday")
    #expect(SummaryCleaner.clean("Follow-up:\nThanks for the call. Next step: I send the contract.") == "Thanks for the call. Next step: I send the contract.")
}

@Test func summaryCleanerKeepsRealContent() {
    #expect(SummaryCleaner.clean("Summary: We agreed to ship on Friday.") == "We agreed to ship on Friday.")
    let real = "We discussed the roadmap and the hiring plan.\n\nDecisions:\n- Ship Friday"
    #expect(SummaryCleaner.clean(real) == real)
    // A first line that merely starts with a scaffolding word is content.
    #expect(SummaryCleaner.clean("Decisions were made quickly that day.") == "Decisions were made quickly that day.")
}

@Test func summaryPromptHasNoLabelsToEcho() {
    let message = PromptBuilder.summaryMessage(transcript: [], notes: "")
    #expect(message.contains("Write only the notes"))
    #expect(!message.contains("Shape:"))
}

@Test func summaryPromptCarriesStructureAndPeople() {
    let message = PromptBuilder.summaryMessage(
        transcript: [TranscriptSegment(channel: "them", text: "What is your salary expectation?", isFinal: true)],
        notes: "", title: "KNIME Interview", attendees: ["Christian Birkhold", "Nils Effmert"])
    #expect(message.contains("## Overview"))
    #expect(message.contains("## Key points"))
    #expect(message.contains("## Action items"))
    #expect(message.contains("KNIME Interview"))
    #expect(message.contains("Christian Birkhold"))
}

@Test func summaryCleanerKeepsMarkdownHeadings() {
    let notes = "## Overview\nWe discussed the role.\n\n## Decisions\n- Start in January"
    #expect(SummaryCleaner.clean(notes) == notes)
    // An echoed scaffold lead still goes, heading or not.
    #expect(SummaryCleaner.clean("### Shape:\n## Overview\nWe discussed the role.") == "## Overview\nWe discussed the role.")
}

@Test func answerHighlightMarksBoldAndFigures() {
    let runs = AnswerHighlight.runs(in: "I led **people operations** for 42 people and cut cost by 18%.")
    #expect(runs.contains(AnswerHighlight.Run(text: "people operations", style: .emphasis)))
    #expect(runs.contains(AnswerHighlight.Run(text: "42", style: .figure)))
    #expect(runs.contains(AnswerHighlight.Run(text: "18%", style: .figure)))
    #expect(!runs.contains { $0.text.contains("**") })
    let plain = AnswerHighlight.runs(in: "No marks at all.")
    #expect(plain == [AnswerHighlight.Run(text: "No marks at all.", style: .plain)])
}

// MARK: - Issue report text (S-038)

@Test func issueTitleComesFromTheFirstLine() {
    #expect(IssueReport.title("Overlay buttons do nothing\nMore detail here.") == "Overlay buttons do nothing")
    #expect(IssueReport.title("   \n") == "Issue in InterviewAI")
    #expect(IssueReport.title(String(repeating: "a", count: 120)).count == 80)
}

@Test func issueBodyCarriesTheContextLine() {
    let body = IssueReport.body(description: "It broke.  \n", version: "1.4.5", macOS: "15.1", engine: "parakeetUltra")
    #expect(body.hasPrefix("It broke."))
    #expect(body.contains("Filed from InterviewAI 1.4.5 on macOS 15.1. Transcription engine: parakeetUltra."))
}

@Test func issueWebURLPrefillsTitleAndBody() {
    let url = IssueReport.webURL(description: "It broke", version: "1.4.5", macOS: "15.1", engine: "parakeetUltra")
    #expect(url?.absoluteString.hasPrefix("https://github.com/splashdeluxe/InterviewAI/issues/new?") == true)
    #expect(url?.absoluteString.contains("title=It%20broke") == true)
}

// MARK: - Echo filter (1.5.0)

@Test("Echo filter drops the mic copy of a line the other side just said")
func echoDropsMicCopy() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let them = TranscriptSegment(channel: "them", text: "What is your salary expectation for this role?", at: t0, isFinal: true)
    let index = EchoFilter.echoIndex(text: "what is your salary expectation for this role", channel: "me", recent: [them], now: t0.addingTimeInterval(1.5))
    #expect(index == 0)
}

@Test("Echo filter finds the earlier mic copy when the real line lands second")
func echoFindsPromoteCase() {
    let t0 = Date(timeIntervalSince1970: 2_000)
    let me = TranscriptSegment(channel: "me", text: "How do you run onboarding for a remote team?", at: t0, isFinal: true)
    let index = EchoFilter.echoIndex(text: "How do you run onboarding for a remote team?", channel: "them", recent: [me], now: t0.addingTimeInterval(4))
    #expect(index == 0)
}

@Test("Echo filter keeps genuine repeats and same-channel lines")
func echoKeepsGenuine() {
    let t0 = Date(timeIntervalSince1970: 3_000)
    let them = TranscriptSegment(channel: "them", text: "How do you run onboarding for a remote team?", at: t0, isFinal: true)
    // Same words, twelve seconds later: a real repeat, not an echo.
    #expect(EchoFilter.echoIndex(text: "How do you run onboarding for a remote team?", channel: "me", recent: [them], now: t0.addingTimeInterval(12)) == nil)
    // Same channel is never an echo.
    #expect(EchoFilter.echoIndex(text: "How do you run onboarding for a remote team?", channel: "them", recent: [them], now: t0.addingTimeInterval(1)) == nil)
    // Different words are never an echo.
    #expect(EchoFilter.echoIndex(text: "Something else entirely was said here.", channel: "me", recent: [them], now: t0.addingTimeInterval(1)) == nil)
}

@Test("Echo filter gives short back-channels a tight window only")
func echoShortLineWindow() {
    let t0 = Date(timeIntervalSince1970: 4_000)
    let them = TranscriptSegment(channel: "them", text: "Yeah, okay.", at: t0, isFinal: true)
    #expect(EchoFilter.echoIndex(text: "Yeah okay", channel: "me", recent: [them], now: t0.addingTimeInterval(1)) == 0)
    #expect(EchoFilter.echoIndex(text: "Yeah okay", channel: "me", recent: [them], now: t0.addingTimeInterval(4)) == nil)
}

// MARK: - Prompt fit (1.5.0)

@Test("Truncate at word cuts on a boundary and marks the cut")
func truncateAtWordCuts() {
    let text = String(repeating: "word ", count: 100)
    let cut = PromptBuilder.truncateAtWord(text, limit: 120)
    #expect(cut.count <= 120)
    #expect(cut.hasSuffix("[Cut here to fit this prompt. The file continues.]"))
    #expect(!cut.dropLast(60).hasSuffix("wor"))
    let short = PromptBuilder.truncateAtWord("short text", limit: 120)
    #expect(short == "short text")
}

@Test("An oversized pinned file lands in the prompt, cut to fit")
func oversizedPinnedFileLands() {
    let big = String(repeating: "onboarding process metric ", count: 3_000)
    let user = PromptBuilder.userMessage(
        action: .answer, typedQuestion: nil, customContext: "",
        documents: [(name: "prep.md", text: big, pinned: true)],
        transcript: [TranscriptSegment(channel: "them", text: "How do you run onboarding?", isFinal: true)],
        screenshotNote: false)
    #expect(user.contains("From prep.md:"))
    #expect(user.contains("[Cut here to fit this prompt. The file continues.]"))
    #expect(user.count < PromptBuilder.contextCharBudget + 2_000)
}

// MARK: - Markdown lite (1.5.0)

@Test("Markdown lite classifies headings, bullets, and paragraphs")
func markdownLiteClassifies() {
    let lines = MarkdownLite.lines("## Identity\nName: Nils\n* Led a team\n- Shipped it\n#### Details\n\n---\nPlain line.")
    #expect(lines.map(\.kind) == [.heading, .paragraph, .bullet, .bullet, .heading, .paragraph])
    #expect(lines[0].text == "Identity")
    #expect(lines[2].text == "Led a team")
    #expect(lines[5].text == "Plain line.")
}

@Test("Echo filter catches a line the other channel cut into pieces")
func echoCatchesSplitChunks() {
    let t0 = Date(timeIntervalSince1970: 5_000)
    let chunk = TranscriptSegment(channel: "them", text: "What is your salary?", at: t0, isFinal: true)
    let whole = "What is your salary expectation for this role?"
    #expect(EchoFilter.echoIndex(text: whole, channel: "me", recent: [chunk], now: t0.addingTimeInterval(2)) == 0)
}

@Test("Echo filter keeps a similar but different question")
func echoKeepsSimilarQuestion() {
    let t0 = Date(timeIntervalSince1970: 6_000)
    let them = TranscriptSegment(channel: "them", text: "What is your salary expectation for this role?", at: t0, isFinal: true)
    #expect(EchoFilter.echoIndex(text: "What is your current salary at your company?", channel: "me", recent: [them], now: t0.addingTimeInterval(2)) == nil)
}

@Test("Echo filter catches the same line worded one word apart")
func echoCatchesOneWordDifference() {
    let t0 = Date(timeIntervalSince1970: 7_000)
    let them = TranscriptSegment(channel: "them", text: "What is your salary expect?", at: t0, isFinal: true)
    #expect(EchoFilter.echoIndex(text: "What is your salary expectation?", channel: "me", recent: [them], now: t0.addingTimeInterval(2)) == 0)
}

@Test func eventMatcherPicksTheOverlappingEvent() {
    let base = Date(timeIntervalSince1970: 100_000)
    func event(_ title: String, _ startOffset: TimeInterval, _ endOffset: TimeInterval) -> UpcomingEvent {
        UpcomingEvent(id: title, title: title, start: base.addingTimeInterval(startOffset), end: base.addingTimeInterval(endOffset), attendees: [], calendarName: "Work")
    }
    let standup = event("Standup", -3600, -1800)
    let interview = event("KNIME Interview", 600, 2400)
    let picked = EventMatcher.pick(events: [standup, interview], sessionStart: base, sessionEnd: base.addingTimeInterval(1800))
    #expect(picked?.title == "KNIME Interview")
}

@Test func eventMatcherPrefersLongestOverlapAndToleratesEarlyStart() {
    let base = Date(timeIntervalSince1970: 200_000)
    func event(_ title: String, _ startOffset: TimeInterval, _ endOffset: TimeInterval) -> UpcomingEvent {
        UpcomingEvent(id: title, title: title, start: base.addingTimeInterval(startOffset), end: base.addingTimeInterval(endOffset), attendees: [], calendarName: "Work")
    }
    // Session started 10 minutes before the event: still its event.
    let early = EventMatcher.pick(events: [event("Call", 600, 2400)], sessionStart: base, sessionEnd: base.addingTimeInterval(900))
    #expect(early?.title == "Call")
    // Two overlapping events: the one covering more of the session wins.
    let short = event("Short", 0, 600)
    let long = event("Long", -600, 3600)
    let picked = EventMatcher.pick(events: [short, long], sessionStart: base, sessionEnd: base.addingTimeInterval(1800))
    #expect(picked?.title == "Long")
    // Nothing near the session: no match.
    let none = EventMatcher.pick(events: [event("Far", 7200, 9000)], sessionStart: base, sessionEnd: base.addingTimeInterval(1800))
    #expect(none == nil)
}

@Test func eventMatcherNeverPicksAllDayEvents() {
    let base = Date(timeIntervalSince1970: 300_000)
    func event(_ title: String, _ startOffset: TimeInterval, _ endOffset: TimeInterval, allDay: Bool = false) -> UpcomingEvent {
        UpcomingEvent(id: title, title: title, start: base.addingTimeInterval(startOffset), end: base.addingTimeInterval(endOffset), attendees: [], calendarName: "Work", isAllDay: allDay)
    }
    // An all-day birthday covers the whole session and would win on
    // overlap against everything; it must not be picked at all.
    let birthday = event("Domi's 44th Birthday", -43_200, 43_200, allDay: true)
    #expect(EventMatcher.pick(events: [birthday], sessionStart: base, sessionEnd: base.addingTimeInterval(1800)) == nil)
    // A timed event during the session still wins over the all-day one.
    let call = event("Call with Alan", 300, 2100)
    let picked = EventMatcher.pick(events: [birthday, call], sessionStart: base, sessionEnd: base.addingTimeInterval(1800))
    #expect(picked?.title == "Call with Alan")
}

@Test func summaryPromptFramesTheCalendarLabelAsAHint() {
    let message = PromptBuilder.summaryMessage(
        transcript: [TranscriptSegment(channel: "me", text: "The new club could be my regular place.", isFinal: true)],
        notes: "", title: "Domi's 44th Birthday", attendees: [])
    #expect(message.contains("as a hint only"))
    #expect(message.contains("ignore the label completely"))
    #expect(message.contains("Domi's 44th Birthday"))
    // The follow-up may only address someone the transcript names.
    #expect(message.contains("keep the greeting general"))
    // No single-channel warning when both sides were captured.
    #expect(!message.contains("Only my side of this call was captured"))
}

@Test func summaryPromptWarnsOnSingleChannel() {
    let message = PromptBuilder.summaryMessage(
        transcript: [TranscriptSegment(channel: "me", text: "Just me talking.", isFinal: true)],
        notes: "", singleChannel: true)
    #expect(message.contains("Only my side of this call was captured"))
    #expect(message.contains("Do not attribute statements to any other named person"))
}

@Test func transcriptExportMarkdownCarriesTheMeeting() {
    let date = Date(timeIntervalSince1970: 300_000)
    let segments = [
        TranscriptSegment(channel: "them", text: "What is your salary expectation?", isFinal: true),
        TranscriptSegment(channel: "me", text: "EUR 95,000.", isFinal: true),
        TranscriptSegment(channel: "me", text: "partial draft", isFinal: false),
    ]
    let md = TranscriptExport.markdown(title: "KNIME Interview", date: date, attendees: ["Christian Birkhold"], location: "Google Meet", segments: segments, summary: "## Overview\nGood talk.")
    #expect(md.hasPrefix("# KNIME Interview"))
    #expect(md.contains("Invited: Christian Birkhold"))
    #expect(md.contains("Location: Google Meet"))
    #expect(md.contains("**Them:** What is your salary expectation?"))
    #expect(md.contains("**Me:** EUR 95,000."))
    #expect(!md.contains("partial draft"))
    #expect(md.contains("## Overview"))
}

@Test func transcriptExportFileNameIsSafe() {
    let date = Date(timeIntervalSince1970: 300_000)
    let name = TranscriptExport.fileName(title: "KNIME: Interview / Director", date: date)
    #expect(name.hasPrefix("KNIME-Interview-Director-"))
    #expect(name.hasSuffix(".md"))
    #expect(!name.contains(" "))
    #expect(!name.contains("/"))
    #expect(TranscriptExport.fileName(title: "///", date: date).hasPrefix("Meeting-"))
}

@Test func answerLanguageDetectsTheOtherSidesLanguage() {
    let german = ["Können Sie mir sagen, wie die Rolle im Team organisiert ist und welche Aufgaben im ersten Jahr am wichtigsten wären?"]
    #expect(AnswerLanguage.detect(in: german) == "German")
    let english = ["Could you tell me how the role is set up in the team and what would matter most in the first year?"]
    #expect(AnswerLanguage.detect(in: english) == "English")
    // A greeting is not a language sample: no instruction at all.
    #expect(AnswerLanguage.detect(in: ["Hallo!"]) == nil)
    #expect(AnswerLanguage.detect(in: []) == nil)
}

@Test func answerLanguagePinnedSettingWinsOverDetection() {
    let german = ["Können Sie mir sagen, wie die Rolle im Team organisiert ist und welche Aufgaben im ersten Jahr am wichtigsten wären?"]
    #expect(AnswerLanguage.resolve(setting: "English", themLines: german) == "English")
    #expect(AnswerLanguage.resolve(setting: "", themLines: german) == "German")
    #expect(AnswerLanguage.resolve(setting: "  ", themLines: []) == nil)
}

@Test func answerLanguageReachesBothPromptLayers() {
    let system = PromptBuilder.systemPrompt(modePrompt: "MODE", answerLanguage: "German")
    #expect(system.contains("write every answer in German"))
    let plain = PromptBuilder.systemPrompt(modePrompt: "MODE")
    #expect(!plain.contains("Answer language"))
    let segments = [TranscriptSegment(channel: "them", text: "Wie ist das Gehalt?", isFinal: true)]
    let user = PromptBuilder.userMessage(action: nil, typedQuestion: nil, customContext: "", documents: [], transcript: segments, screenshotNote: false, answerLanguage: "German")
    #expect(user.hasSuffix("Write the answer in German."))
    let userPlain = PromptBuilder.userMessage(action: nil, typedQuestion: nil, customContext: "", documents: [], transcript: segments, screenshotNote: false)
    #expect(!userPlain.contains("Write the answer in"))
}
