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
        audio.start(localeIdentifier: locale, engine: engineKind, whisperModel: whisperModel, diarize: diarize)
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        settleTask?.cancel()
        audio.stop()
        status = "Stopped"
        guard let model, !finalSegments.isEmpty else { linkedEvent = nil; return }
        let meeting = model.saveMeeting(from: self)
        summarize(meeting: meeting)
        diarize(meeting: meeting)
        linkedEvent = nil
    }

    private func receive(channel: String, text: String, isFinal: Bool, seconds: Double?) {
        if isFinal {
            partials[channel] = nil
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
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

    /// When the other side's line settles, answer it after a short pause.
    /// A new line cancels the pending answer, so only the last question
    /// of a run is answered.
    private func scheduleAutoAnswer() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self, isListening, !isAnswering else { return }
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
        let system = PromptBuilder.systemPrompt(modePrompt: mode.definition.prompt)
        let user = PromptBuilder.userMessage(
            action: action,
            typedQuestion: typedQuestion,
            customContext: combinedContext,
            documents: model.contextDocuments(),
            transcript: displaySegments,
            screenshotNote: screenshot != nil
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

    // MARK: Summary

    private func summarize(meeting: Meeting) {
        let config = ProviderSettings.config()
        let apiKey = ProviderSettings.apiKey
        let segments = meeting.segments
        let notes = meeting.notes
        Task {
            let text = try? await Brain.complete(
                config: config, apiKey: apiKey,
                system: "You write short, factual meeting notes. Use only the transcript. No invented names, numbers, or decisions.",
                user: PromptBuilder.summaryMessage(transcript: segments, notes: notes)
            )
            guard let text, !text.isEmpty else { return }
            let parts = text.components(separatedBy: "===")
            meeting.summary = SummaryCleaner.clean(parts.first ?? "")
            if parts.count > 1 {
                meeting.followUp = SummaryCleaner.clean(parts[1])
            }
            try? meeting.modelContext?.save()
        }
    }
}
