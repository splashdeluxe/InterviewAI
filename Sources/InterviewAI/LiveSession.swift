import Foundation
import InterviewAIKit

/// One live session: capture, transcript, streamed answers, and the save
/// at the end. Views read its state; AppModel wires it to the store.
@Observable
final class LiveSession {
    @ObservationIgnored weak var model: AppModel?

    @ObservationIgnored private let audio = AudioEngine()
    var isListening = false
    /// A paused session is still listening: capture is stopped, the
    /// transcript and the session clock are frozen, and Resume picks
    /// the same session up. Set by pause()/resume(), never directly.
    var isPaused = false
    /// The pause-aware session clock: offsets and the saved duration
    /// read it, so paused time never counts as session time.
    @ObservationIgnored private var clock: SessionClock?
    /// The capture settings chosen at start, reused verbatim by a
    /// resume so a paused session comes back exactly as it left.
    @ObservationIgnored private var captureLocale = "en-US"
    @ObservationIgnored private var captureEngine: TranscriptionEngineKind = .parakeetUltra
    @ObservationIgnored private var captureWhisper = "large-v3-v20240930_626MB"
    @ObservationIgnored private var captureDiarize = true
    var status = "Not listening"
    var finalSegments: [TranscriptSegment] = []
    /// The current unfinished line per channel ("them", "me").
    var partials: [String: String] = [:]
    var answer = ""
    var isAnswering = false
    var answerError: String?
    var notes = ""
    var startedAt: Date?
    /// The calendar event this session was started from, when it was.
    /// Its title names the saved meeting, and its id is stored on it.
    var linkedEvent: UpcomingEvent?
    /// What the user said this session is, in the setup sheet shown
    /// before recording starts: who it is with, what it is about. It
    /// feeds the answer and suggestion prompts, and names the saved
    /// meeting when no calendar event does.
    var sessionContext = ""
    /// The user picked "just a call" at setup: the save must not go
    /// hunting for a calendar event to attach after the fact.
    var eventDeclined = false
    /// Who is on the other side, when a source already knows: the
    /// setup sheet's Talking With field, or the one invited person on
    /// the session's calendar event. Their lines carry this name from
    /// the first line on, live, instead of "Them". Empty when nobody
    /// is known, and the transcript honestly stays generic.
    var otherSpeakerName = ""
    /// The user's own first name from Settings, for their lines.
    @ObservationIgnored private var mySpeakerFirstName = ""

    /// The name the user gave for themself in Settings, General.
    static var myNameSetting: String {
        UserDefaults.standard.string(forKey: "speaker.myName") ?? ""
    }
    /// Set by the views when the user asks to start: the Live page
    /// answers by presenting the setup sheet.
    var setupRequested = false
    /// Plain words on the Live page and the overlay when the other
    /// side has never been heard: answers and suggestions follow the
    /// other side's channel, so a silent one means both are paused,
    /// and the user should know why instead of guessing.
    var otherSideWarning: String?
    /// A per-session Save Audio choice from the setup sheet, winning
    /// over the standing setting for this one session.
    @ObservationIgnored private var audioOverride: Bool?
    var pendingScreenshot: Data?
    /// Session audio: when the Save Session Audio setting is on, a
    /// recorder is handed to the engine at start and the finished file
    /// is attached to the saved meeting at stop.
    @ObservationIgnored private var recorder: SessionAudioRecorder?
    @ObservationIgnored private var pendingAudioName: String?
    @ObservationIgnored private var audioWasRequested = false
    var audioRecordingActive = false
    /// Automatic Suggestions (Hedy plan, phase 2): proactive tips the
    /// engine offers while the session runs. Every kept tip lands in
    /// `suggestions`; the newest one is also the overlay card until it
    /// is dismissed or replaced.
    var suggestions: [Suggestion] = []
    var currentSuggestion: Suggestion?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var lastSuggestionCycle: Date?
    var autoAnswer: Bool = UserDefaults.standard.object(forKey: "session.autoAnswer") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoAnswer, forKey: "session.autoAnswer") }
    }

    @ObservationIgnored private var answerTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    var displaySegments: [TranscriptSegment] {
        var lines = finalSegments
        for channel in ["them", "me"] {
            if let partial = partials[channel], !partial.isEmpty {
                lines.append(TranscriptSegment(channel: channel, text: partial, isFinal: false))
            }
        }
        return lines
    }

    var duration: Double {
        if let clock { return clock.elapsed(at: Date.now) }
        guard let startedAt else { return 0 }
        return Date.now.timeIntervalSince(startedAt)
    }

    var meetingTitle: String {
        if let linkedEvent { return linkedEvent.title }
        if !sessionContext.isEmpty { return sessionContext }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let modeName = model?.activeMode().definition.name ?? "Meeting"
        return "\(modeName) · \(formatter.string(from: startedAt ?? Date.now))"
    }

    // MARK: Start and stop

    func toggle() {
        if isListening {
            stop()
        } else {
            // A plain start (hotkey, menu) carries no setup choices:
            // clear whatever a previous planned start left behind.
            linkedEvent = nil
            sessionContext = ""
            eventDeclined = false
            otherSpeakerName = ""
            audioOverride = nil
            start()
        }
    }

    /// Start listening for a calendar event: the meeting takes the
    /// event's title, and the event link is saved with it.
    func start(event: UpcomingEvent) {
        linkedEvent = event
        sessionContext = ""
        eventDeclined = false
        otherSpeakerName = SpeakerNames.singleOther(
            attendees: event.attendees, organizer: event.organizer, myName: Self.myNameSetting
        ) ?? ""
        start()
    }

    /// Start with the setup sheet's choices: the event the user
    /// confirmed (or none, for a call that is not an appointment), the
    /// context line they typed, and this session's Save Audio choice.
    func startPlanned(event: UpcomingEvent?, context: String, saveAudio: Bool, talkingWith: String = "") {
        linkedEvent = event
        eventDeclined = event == nil
        sessionContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = talkingWith.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            otherSpeakerName = typed
        } else if let event {
            otherSpeakerName = SpeakerNames.singleOther(
                attendees: event.attendees, organizer: event.organizer, myName: Self.myNameSetting
            ) ?? ""
        } else {
            otherSpeakerName = ""
        }
        audioOverride = saveAudio
        start()
    }

    func start() {
        guard !isListening else { return }
        finalSegments = []
        partials = [:]
        answer = ""
        answerError = nil
        startedAt = Date.now
        clock = SessionClock(startedAt: startedAt ?? Date.now)
        isPaused = false
        isListening = true
        status = "Starting"
        captureLocale = UserDefaults.standard.string(forKey: "speech.locale") ?? "en-US"
        captureEngine = TranscriptionEngineKind(rawValue: UserDefaults.standard.string(forKey: "transcription.engine") ?? "parakeetUltra") ?? .parakeetUltra
        captureWhisper = UserDefaults.standard.string(forKey: "transcription.whisperModel") ?? "large-v3-v20240930_626MB"
        captureDiarize = UserDefaults.standard.object(forKey: "transcription.diarize") as? Bool ?? true
        audioWasRequested = audioOverride ?? UserDefaults.standard.bool(forKey: "sessionAudio.enabled")
        audioOverride = nil
        otherSideWarning = nil
        var activeRecorder: SessionAudioRecorder?
        if audioWasRequested {
            let name = UUID().uuidString + ".m4a"
            let candidate = SessionAudioRecorder(fileURL: SessionAudioStore.url(fileName: name))
            if candidate.start() {
                activeRecorder = candidate
                pendingAudioName = name
                audioRecordingActive = true
            }
        }
        recorder = activeRecorder
        suggestions = []
        currentSuggestion = nil
        lastSuggestionCycle = nil
        beginCapture(resume: false)
        startSuggestionLoop()
    }

    /// Wire the engine's callbacks and start capturing with the
    /// session's stored settings. A resume keeps the recorder and the
    /// diarization collector, so the session continues as one.
    private func beginCapture(resume: Bool) {
        audio.onSegment = { [weak self] channel, text, isFinal, seconds in
            DispatchQueue.main.async { self?.receive(channel: channel, text: text, isFinal: isFinal, seconds: seconds) }
        }
        audio.onStatus = { [weak self] message in
            DispatchQueue.main.async { self?.status = message }
        }
        mySpeakerFirstName = SpeakerNames.firstName(of: Self.myNameSetting)
        audio.start(localeIdentifier: captureLocale, engine: captureEngine, whisperModel: captureWhisper, diarize: captureDiarize, recorder: recorder, keepCollector: resume)
    }

    private func startSuggestionLoop() {
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, isListening, !isPaused else { return }
                checkOtherSide()
                await runSuggestionCycleIfDue()
            }
        }
    }

    /// Freeze the session: capture stops, the clock stops, the
    /// transcript stays. Nothing is saved and nothing is lost; the
    /// microphones and screen capture are released while paused.
    func pause() {
        guard isListening, !isPaused else { return }
        clock?.beginPause(at: Date.now)
        isPaused = true
        settleTask?.cancel()
        suggestionTask?.cancel()
        audio.stop()
        partials = [:]
        status = "Paused"
    }

    /// Pick a paused session up where it left off: same transcript,
    /// same recorder, same diarization timeline, clock running again.
    func resume() {
        guard isListening, isPaused else { return }
        clock?.endPause(at: Date.now)
        isPaused = false
        status = "Starting"
        beginCapture(resume: true)
        startSuggestionLoop()
    }

    /// Throw the session away: capture stops, the recording is
    /// deleted, and nothing is saved. The user's Delete choice in the
    /// Session Controls, never a fallback for a failed save.
    func discard() {
        guard isListening else { return }
        isListening = false
        isPaused = false
        clock = nil
        settleTask?.cancel()
        suggestionTask?.cancel()
        answerTask?.cancel()
        audio.stop()
        if let recorder, let pendingAudioName {
            recorder.stop { _ in SessionAudioStore.delete(fileName: pendingAudioName) }
        }
        recorder = nil
        pendingAudioName = nil
        audioWasRequested = false
        audioRecordingActive = false
        finalSegments = []
        partials = [:]
        suggestions = []
        currentSuggestion = nil
        answer = ""
        answerError = nil
        otherSideWarning = nil
        linkedEvent = nil
        startedAt = nil
        status = "Session deleted. Nothing was saved."
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        // Ending from a pause: the clock already excludes the open
        // pause from the duration, and the engine is already stopped,
        // so the save below runs exactly as an unpaused stop.
        isPaused = false
        settleTask?.cancel()
        suggestionTask?.cancel()
        audio.stop()
        status = "Stopped"
        let activeRecorder = recorder
        let audioName = pendingAudioName
        let wasRequested = audioWasRequested
        recorder = nil
        pendingAudioName = nil
        audioWasRequested = false
        audioRecordingActive = false
        var saved: Meeting?
        if let model, !finalSegments.isEmpty {
            saved = model.saveMeeting(from: self)
            if let saved {
                if !suggestions.isEmpty {
                    saved.suggestionsJSON = Suggestion.encode(suggestions)
                    try? saved.modelContext?.save()
                }
                summarize(meeting: saved)
                diarize(meeting: saved)
            }
        }
        linkedEvent = nil
        guard let activeRecorder, let audioName else {
            if wasRequested, saved != nil {
                status = "Session saved. Audio recording could not start, but the transcript is complete."
            }
            return
        }
        // The file is finalised off the main thread; the meeting only
        // points at it once it is really on disk. A failed recording
        // deletes its partial file and the session says so plainly.
        activeRecorder.stop { [weak self] ok in
            DispatchQueue.main.async {
                if ok, let saved {
                    saved.audioFileName = audioName
                    try? saved.modelContext?.save()
                } else {
                    SessionAudioStore.delete(fileName: audioName)
                    if saved != nil {
                        let reason = activeRecorder.failureSummary
                        self?.status = reason.isEmpty
                            ? "Session saved. The audio recording failed, but the transcript is complete."
                            : "Session saved. The audio recording failed (\(reason)), but the transcript is complete."
                    }
                }
            }
        }
    }

    private func receive(channel: String, text: String, isFinal: Bool, seconds: Double?) {
        if isFinal {
            partials[channel] = nil
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // On speakers the mic hears the other side too, so their
            // lines land twice. Drop the echo copy. If the mic copy
            // landed first and the real system-audio line arrives now,
            // promote the earlier copy to "them" instead, so Auto
            // Answer still fires on it.
            if let echoIndex = EchoFilter.echoIndex(text: trimmed, channel: channel, recent: finalSegments) {
                if channel == "them" {
                    finalSegments[echoIndex].channel = "them"
                    // The promoted copy was heard as the user's own
                    // line, so it may carry their name; as an other
                    // side line it carries the other name, or none.
                    finalSegments[echoIndex].speakerLabel = otherSpeakerName.isEmpty ? nil : otherSpeakerName
                    otherSideWarning = nil
                    if autoAnswer, isListening { scheduleAutoAnswer() }
                }
                return
            }
            var segment = TranscriptSegment(channel: channel, text: trimmed, isFinal: true)
            if channel == "them", !otherSpeakerName.isEmpty {
                segment.speakerLabel = otherSpeakerName
            }
            if channel == "me", !mySpeakerFirstName.isEmpty {
                segment.speakerLabel = mySpeakerFirstName
            }
            if let seconds, let clock {
                segment.duration = seconds
                segment.startOffset = max(0, clock.elapsed(at: Date.now) - seconds)
            }
            finalSegments.append(segment)
            if channel == "them" { otherSideWarning = nil }
            if let target = Self.translationTarget {
                enqueueTranslation(segmentID: segment.id, text: trimmed, target: target)
            }
            if channel == "them", autoAnswer, isListening {
                scheduleAutoAnswer()
            }
        } else {
            partials[channel] = text
        }
    }

    /// Once a session is a minute and a half in and the user has
    /// clearly been talking, a completely silent other side is not a
    /// quiet call, it is a capture problem: the call is running on
    /// another device, or its app is not the one playing sound here.
    /// Auto Answer and suggestions both key off the other side's
    /// lines, so without this warning the app looks merely dumb while
    /// it is actually deaf. Checked on the suggestion ticker; clears
    /// itself the moment a real other-side line lands.
    private func checkOtherSide() {
        guard otherSideWarning == nil, let startedAt else { return }
        guard Date.now.timeIntervalSince(startedAt) > 90 else { return }
        let themCount = finalSegments.filter { $0.channel == "them" }.count
        let meCount = finalSegments.filter { $0.channel == "me" }.count
        if themCount == 0 && meCount >= 8 {
            otherSideWarning = "I can't hear the other side, so answers and suggestions are paused. They follow the other side's words, and none have arrived. If this call is on your phone or another device, move it to this Mac. On this Mac, check the call app is the one playing the sound."
        }
    }

    // MARK: Translation

    /// The target language set in Settings, Speech, or nil when off.
    /// Read per line, so toggling it mid-call takes effect at once.
    private static var translationTarget: String? {
        let value = UserDefaults.standard.string(forKey: "transcription.translateTo") ?? ""
        return value.isEmpty ? nil : value
    }

    @ObservationIgnored private var translationChain: Task<Void, Never>?

    /// Translations run one at a time through the session's provider, so
    /// lines land in order and the local model is not hammered.
    private func enqueueTranslation(segmentID: UUID, text: String, target: String) {
        let previous = translationChain
        translationChain = Task { [weak self] in
            await previous?.value
            let translated = try? await Brain.complete(
                config: ProviderSettings.config(), apiKey: ProviderSettings.apiKey,
                system: TranslationPrompts.system(target: target), user: text
            )
            let cleaned = translated?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleaned.isEmpty, cleaned != text else { return }
            if let index = self?.finalSegments.firstIndex(where: { $0.id == segmentID }) {
                self?.finalSegments[index].translatedText = cleaned
            }
        }
    }

    // MARK: Speakers

    /// After the call, work out who spoke when on the other side and
    /// label the saved lines Speaker 1, Speaker 2, and so on. Runs
    /// beside the summary; the meeting updates in place when it lands.
    /// Then the names: when exactly one person is known to have been
    /// on the other side, their name replaces the generic label. When
    /// several people were invited, the deep model may match the
    /// numbered speakers to invited names, but only with proof inside
    /// the transcript, and only ever from the invited list
    /// (SpeakerNames.parseMapping enforces the list), so a name can
    /// never be invented here.
    private func diarize(meeting: Meeting) {
        let segments = meeting.segments
        let attendeeNames = meeting.attendees.isEmpty ? [] : meeting.attendees.components(separatedBy: ", ")
        let candidates = SpeakerNames.candidates(attendees: attendeeNames, myName: Self.myNameSetting)
        let knownSingle = otherSpeakerName.isEmpty
            ? SpeakerNames.singleOther(attendees: attendeeNames, myName: Self.myNameSetting)
            : otherSpeakerName
        var passCandidates = candidates
        if let knownSingle, !passCandidates.contains(knownSingle) { passCandidates.append(knownSingle) }
        let samples = audio.themAudio
        guard samples.count > 16_000 * 20 else {
            // Too short to diarize, but a single known name still
            // names the other side's lines that carry no name yet.
            var applied = false
            if let knownSingle {
                let updated = SpeakerNames.applying(segments: segments, mapping: ["Them": knownSingle])
                if updated != segments {
                    meeting.transcriptJSON = TranscriptSegment.encode(updated)
                    try? meeting.modelContext?.save()
                    applied = true
                }
            }
            if !applied, segments.contains(where: { $0.channel == "them" && $0.isFinal }) {
                meeting.diarizationNote = DiarizationNotes.tooShort
                try? meeting.modelContext?.save()
            }
            return
        }
        Task {
            guard let ranges = try? await DiarizationRuntime.shared.diarize(samples: samples),
                  !ranges.isEmpty else {
                var applied = false
                if let knownSingle {
                    let updated = SpeakerNames.applying(segments: segments, mapping: ["Them": knownSingle])
                    if updated != segments {
                        meeting.transcriptJSON = TranscriptSegment.encode(updated)
                        try? meeting.modelContext?.save()
                        applied = true
                    }
                }
                if !applied {
                    meeting.diarizationNote = DiarizationNotes.unavailable
                    try? meeting.modelContext?.save()
                }
                return
            }
            let windows: [(start: Double, end: Double)?] = segments.map { segment in
                guard segment.channel == "them",
                      let start = segment.startOffset, let duration = segment.duration else { return nil }
                return (start: start, end: start + duration)
            }
            let labels = SpeakerAssigner.labels(windows: windows, ranges: ranges)
            var updated = segments
            var changed = false
            for (index, label) in labels.enumerated() {
                // A line already carrying the known single name keeps
                // it until the evidence pass below says otherwise:
                // overwriting it with Speaker 1 and failing to map
                // back would take a real name away.
                if let label, updated[index].speakerLabel != label,
                   knownSingle == nil || updated[index].speakerLabel != knownSingle {
                    updated[index].speakerLabel = label
                    changed = true
                }
            }
            // One voice on the other side and one known person: the
            // numbered label becomes the name.
            let themNames = Set(updated.filter { $0.channel == "them" }.map(\.speakerName))
            if themNames.count == 1, let only = themNames.first, let knownSingle, only != knownSingle {
                updated = SpeakerNames.applying(segments: updated, mapping: [only: knownSingle])
                changed = true
            }
            if changed {
                meeting.transcriptJSON = TranscriptSegment.encode(updated)
                try? meeting.modelContext?.save()
            }
            // The collector holds one hour; past it, later voices
            // were never checked, and the meeting says so.
            if samples.count >= 16_000 * 60 * 60 - 16_000 {
                meeting.diarizationNote = DiarizationNotes.firstHourOnly
                try? meeting.modelContext?.save()
            }
            // The evidence pass for everyone still numbered.
            let generic = SpeakerNames.distinctNames(segments: updated).filter { $0.hasPrefix("Speaker ") }
            guard !generic.isEmpty, !passCandidates.isEmpty else { return }
            let outcome = try? await DeepWork.complete(
                system: SpeakerNamePrompts.system,
                user: SpeakerNamePrompts.user(
                    labels: generic, candidates: passCandidates,
                    transcript: TranscriptSegment.plainText(updated)
                ),
                maxTokens: 200
            )
            guard let outcome else { return }
            let mapping = SpeakerNames.parseMapping(outcome.text, labels: generic, candidates: passCandidates)
            guard !mapping.isEmpty else { return }
            let named = SpeakerNames.applying(segments: updated, mapping: mapping)
            if named != updated {
                meeting.transcriptJSON = TranscriptSegment.encode(named)
                try? meeting.modelContext?.save()
            }
        }
    }

    /// When the other side's line settles, answer it after a short
    /// pause, when the line earns an answer (see AutoAnswerGate).
    /// A new line cancels the pending answer, so only the last
    /// question of a run is answered. If an answer is still streaming
    /// when the pause ends, wait once for it instead of dropping the
    /// question silently, which read as "auto answer does nothing".
    private func scheduleAutoAnswer() {
        guard let last = finalSegments.last(where: { $0.channel == "them" }),
              AutoAnswerGate.shouldAnswer(last.text) else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self, isListening else { return }
            if isAnswering {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled, isListening, !isAnswering else { return }
            }
            runAction(.answer, typedQuestion: nil)
        }
    }

    // MARK: Answers

    func runAction(_ action: AnswerAction?, typedQuestion: String?) {
        guard let model else { return }
        answerTask?.cancel()
        answer = ""
        answerError = nil
        isAnswering = true

        let mode = model.activeMode()
        let config = ProviderSettings.config()
        let apiKey = ProviderSettings.apiKey
        let screenshot = pendingScreenshot
        var combinedContext = mode.context
        if !sessionContext.isEmpty {
            combinedContext = "This session: \(sessionContext)\n\n" + combinedContext
        }
        let profile = model.profileContext()
        if !profile.isEmpty {
            combinedContext += "\n\n" + profile
        }
        // Answers land in the pinned language from Settings, or match
        // the other side's language when the setting is on Automatic.
        let answerLanguage = AnswerLanguage.resolve(
            setting: UserDefaults.standard.string(forKey: "answers.language") ?? "",
            themLines: displaySegments.filter { $0.channel == "them" && $0.isFinal }.map(\.text)
        )
        let system = PromptBuilder.systemPrompt(modePrompt: mode.definition.prompt, answerLanguage: answerLanguage)
        let user = PromptBuilder.userMessage(
            action: action,
            typedQuestion: typedQuestion,
            customContext: combinedContext,
            documents: model.contextDocuments(),
            transcript: displaySegments,
            screenshotNote: screenshot != nil,
            answerLanguage: answerLanguage
        )
        let imageBase64 = (screenshot != nil && config.visionModel) ? screenshot?.base64EncodedString() : nil
        if screenshot != nil && !config.visionModel {
            answerError = "The screenshot is attached, but the current model cannot read images. Turn on Vision in Settings, Providers, or pick a vision model."
        }
        pendingScreenshot = nil

        answerTask = Task { [weak self] in
            do {
                for try await piece in Brain.stream(config: config, apiKey: apiKey, system: system, user: user, imageBase64: imageBase64) {
                    if Task.isCancelled { return }
                    self?.answer += piece
                }
            } catch {
                self?.answerError = error.localizedDescription
            }
            self?.isAnswering = false
        }
    }

    func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // A typed question is also transcript: it belongs to the meeting.
        finalSegments.append(TranscriptSegment(
            channel: "me", text: trimmed, isFinal: true,
            speakerLabel: mySpeakerFirstName.isEmpty ? nil : mySpeakerFirstName
        ))
        runAction(nil, typedQuestion: trimmed)
    }

    func captureScreenshot() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        Task { [weak self] in
            do {
                let png = try await ScreenCapturer.frontWindowPNG(excludingBundleID: bundleID)
                self?.pendingScreenshot = png
                self?.status = "Screenshot attached to the next answer"
            } catch {
                self?.answerError = "Screenshot failed. Grant Screen Recording in the Permissions tab. (\(error.localizedDescription))"
            }
        }
    }

    // MARK: Automatic Suggestions

    /// One suggestion cycle, when the engine's gate says one is due:
    /// the live model drafts up to three candidate tips from the
    /// recent transcript, and the strict filter keeps at most one.
    /// The filter is a pick-or-none judgement, so the live model
    /// runs it too (changed 2026-11-12, Nils: answers must come
    /// really fast). Routing it through the Deep model loaded the
    /// second, much larger model beside the live one mid-session,
    /// and on a 16 GB Mac that memory pressure is what made live
    /// answers crawl. Deep still does Ask and the meeting notes,
    /// work that happens on demand or after the call. A cycle that
    /// finds nothing, or fails anywhere, is silent: a suggestion is
    /// a bonus, never an error in the answer area. Cycles also skip
    /// while an answer is streaming, so the local model is never
    /// asked for two things at once.
    private func runSuggestionCycleIfDue() async {
        guard !isAnswering, let startedAt, let model else { return }
        let frequency = SuggestionFrequency(rawValue: UserDefaults.standard.string(forKey: "suggestions.frequency") ?? "") ?? .balanced
        let themCount = finalSegments.filter { $0.channel == "them" }.count
        guard SuggestionEngine.shouldEvaluate(now: Date.now, sessionStartedAt: startedAt, lastCycleAt: lastSuggestionCycle, frequency: frequency, themSegmentCount: themCount) else { return }
        lastSuggestionCycle = Date.now
        let window = Array(finalSegments.suffix(14))
        let transcript = TranscriptSegment.plainText(window)
        let previous = suggestions.map(\.text)
        do {
            let draft = try await Brain.complete(
                config: ProviderSettings.config(), apiKey: ProviderSettings.apiKey,
                system: SuggestionPrompts.draftSystem,
                user: SuggestionPrompts.draftUser(modeName: model.activeMode().definition.name, transcript: transcript, previousTips: previous, context: sessionContext),
                maxTokens: 350
            )
            let fresh = SuggestionEngine.parseCandidates(draft).filter { !SuggestionEngine.isDuplicate($0.text, previous: previous) }
            guard !fresh.isEmpty else { return }
            let scored = try await Brain.complete(
                config: ProviderSettings.config(), apiKey: ProviderSettings.apiKey,
                system: SuggestionPrompts.scoreSystem(frequency: frequency),
                user: SuggestionPrompts.scoreUser(candidates: fresh, transcript: transcript),
                maxTokens: 60
            )
            guard let pick = SuggestionEngine.parsePick(scored, candidates: fresh) else { return }
            suggestions.append(pick)
            let showCard = UserDefaults.standard.object(forKey: "suggestions.overlayCard") as? Bool ?? true
            if showCard { currentSuggestion = pick }
        } catch {
            // Silent by design, see the note above.
        }
    }

    func dismissSuggestion() {
        currentSuggestion = nil
    }

    /// The card's follow-up tap: the tip becomes the question, so the
    /// model works it out against the live transcript and context.
    func useSuggestion() {
        guard let tip = currentSuggestion else { return }
        currentSuggestion = nil
        ask(tip.text)
    }

    // MARK: Summary

    private func summarize(meeting: Meeting) {
        let segments = meeting.segments
        let notes = meeting.notes
        let title = meeting.title
        let attendees = meeting.attendees.isEmpty ? [] : meeting.attendees.components(separatedBy: ", ")
        // A session whose other side never arrived (the call ran on
        // another device) has no Them lines at all: the summary must
        // know, or it invents a second speaker's positions.
        let singleChannel = !segments.contains { $0.channel == "them" }
        Task {
            // A summary is a document, not a spoken answer: it gets a
            // bigger token budget than the 400 the answer path uses.
            // At 400 the notes were cut off before they said anything.
            // It is also Deep work: the big model writes it when
            // Dual-Brain is on, the live model when it is not.
            let outcome = try? await DeepWork.complete(
                system: "You write meeting notes from a transcript: clear, complete, factual. Use only the transcript. No invented names, numbers, decisions, or roles.",
                user: PromptBuilder.summaryMessage(transcript: segments, notes: notes, title: title, attendees: attendees, singleChannel: singleChannel),
                maxTokens: 1200
            )
            guard let outcome, !outcome.text.isEmpty else { return }
            if outcome.fellBack {
                status = "Summary written by the live model; the deep model was unavailable."
            }
            let text = outcome.text
            let parts = text.components(separatedBy: "===")
            meeting.summary = SummaryCleaner.clean(parts.first ?? "")
            if parts.count > 1 {
                meeting.followUp = SummaryCleaner.clean(parts[1])
            }
            try? meeting.modelContext?.save()
        }
    }
}
