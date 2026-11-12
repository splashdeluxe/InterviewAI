import Foundation
import InterviewAIKit

/// One live session: capture, transcript, streamed answers, and the save
/// at the end. Views read its state; AppModel wires it to the store.
@Observable
final class LiveSession {
    @ObservationIgnored weak var model: AppModel?

    @ObservationIgnored private let audio = AudioEngine()
    var isListening = false
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
        guard let startedAt else { return 0 }
        return Date.now.timeIntervalSince(startedAt)
    }

    var meetingTitle: String {
        if let linkedEvent { return linkedEvent.title }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let modeName = model?.activeMode().definition.name ?? "Meeting"
        return "\(modeName) · \(formatter.string(from: startedAt ?? Date.now))"
    }

    // MARK: Start and stop

    func toggle() { isListening ? stop() : start() }

    /// Start listening for a calendar event: the meeting takes the
    /// event's title, and the event link is saved with it.
    func start(event: UpcomingEvent) {
        linkedEvent = event
        start()
    }

    func start() {
        guard !isListening else { return }
        finalSegments = []
        partials = [:]
        answer = ""
        answerError = nil
        startedAt = Date.now
        isListening = true
        status = "Starting"
        audio.onSegment = { [weak self] channel, text, isFinal, seconds in
            DispatchQueue.main.async { self?.receive(channel: channel, text: text, isFinal: isFinal, seconds: seconds) }
        }
        audio.onStatus = { [weak self] message in
            DispatchQueue.main.async { self?.status = message }
        }
        let locale = UserDefaults.standard.string(forKey: "speech.locale") ?? "en-US"
        let engineKind = TranscriptionEngineKind(rawValue: UserDefaults.standard.string(forKey: "transcription.engine") ?? "parakeetUltra") ?? .parakeetUltra
        let whisperModel = UserDefaults.standard.string(forKey: "transcription.whisperModel") ?? "large-v3-v20240930_626MB"
        let diarize = UserDefaults.standard.object(forKey: "transcription.diarize") as? Bool ?? true
        audioWasRequested = UserDefaults.standard.bool(forKey: "sessionAudio.enabled")
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
        audio.start(localeIdentifier: locale, engine: engineKind, whisperModel: whisperModel, diarize: diarize, recorder: activeRecorder)
        suggestions = []
        currentSuggestion = nil
        lastSuggestionCycle = nil
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, isListening else { return }
                await runSuggestionCycleIfDue()
            }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
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
                        self?.status = "Session saved. The audio recording failed, but the transcript is complete."
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
                    if autoAnswer, isListening { scheduleAutoAnswer() }
                }
                return
            }
            var segment = TranscriptSegment(channel: channel, text: trimmed, isFinal: true)
            if let seconds, let startedAt {
                segment.duration = seconds
                segment.startOffset = max(0, Date.now.timeIntervalSince(startedAt) - seconds)
            }
            finalSegments.append(segment)
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
    private func diarize(meeting: Meeting) {
        let samples = audio.themAudio
        guard samples.count > 16_000 * 20 else { return }
        let segments = meeting.segments
        Task {
            guard let ranges = try? await DiarizationRuntime.shared.diarize(samples: samples),
                  !ranges.isEmpty else { return }
            let windows: [(start: Double, end: Double)?] = segments.map { segment in
                guard segment.channel == "them",
                      let start = segment.startOffset, let duration = segment.duration else { return nil }
                return (start: start, end: start + duration)
            }
            let labels = SpeakerAssigner.labels(windows: windows, ranges: ranges)
            var updated = segments
            var changed = false
            for (index, label) in labels.enumerated() {
                if let label, updated[index].speakerLabel != label {
                    updated[index].speakerLabel = label
                    changed = true
                }
            }
            guard changed else { return }
            meeting.transcriptJSON = TranscriptSegment.encode(updated)
            try? meeting.modelContext?.save()
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
        finalSegments.append(TranscriptSegment(channel: "me", text: trimmed, isFinal: true))
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
    /// recent transcript, the strict filter keeps at most one (the
    /// Deep model does the filtering when Dual-Brain is on, through
    /// DeepWork). A cycle that finds nothing, or fails anywhere, is
    /// silent: a suggestion is a bonus, never an error in the answer
    /// area. Cycles also skip while an answer is streaming, so the
    /// local model is never asked for two things at once.
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
                user: SuggestionPrompts.draftUser(modeName: model.activeMode().definition.name, transcript: transcript, previousTips: previous),
                maxTokens: 350
            )
            let fresh = SuggestionEngine.parseCandidates(draft).filter { !SuggestionEngine.isDuplicate($0.text, previous: previous) }
            guard !fresh.isEmpty else { return }
            let outcome = try await DeepWork.complete(
                system: SuggestionPrompts.scoreSystem(frequency: frequency),
                user: SuggestionPrompts.scoreUser(candidates: fresh, transcript: transcript),
                maxTokens: 60
            )
            guard let pick = SuggestionEngine.parsePick(outcome.text, candidates: fresh) else { return }
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
        Task {
            // A summary is a document, not a spoken answer: it gets a
            // bigger token budget than the 400 the answer path uses.
            // At 400 the notes were cut off before they said anything.
            // It is also Deep work: the big model writes it when
            // Dual-Brain is on, the live model when it is not.
            let outcome = try? await DeepWork.complete(
                system: "You write meeting notes from a transcript: clear, complete, factual. Use only the transcript. No invented names, numbers, decisions, or roles.",
                user: PromptBuilder.summaryMessage(transcript: segments, notes: notes, title: title, attendees: attendees),
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
