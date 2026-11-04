import SwiftUI
import InterviewAIKit

/// The in-app setup test: one tap checks the whole chain an answer
/// depends on, with plain pass or fail lines. Built after a test call
/// where the answers were wrong and slow for three separate reasons
/// at once; this makes each one visible before the real call starts.
///
/// 1. The provider answers a real question through the real prompt
///    path (mode prompt, context, restated question), and the reply
///    must actually be right: 1 plus 1 must say 2.
/// 2. The speech model loads.
/// 3. The permissions a session needs are in place.
/// 4. Auto Answer's gate lets a real question through.
@Observable
final class SetupTest {
    struct Line: Identifiable {
        let id = UUID()
        let ok: Bool
        let text: String
    }

    var lines: [Line] = []
    var isRunning = false

    @MainActor
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        lines = []

        // 1. The answer path, end to end.
        let config = ProviderSettings.config()
        let started = Date.now
        do {
            let user = PromptBuilder.userMessage(
                action: .answer, typedQuestion: nil, customContext: "",
                documents: [],
                transcript: [TranscriptSegment(channel: "them", text: "What is 1 plus 1?", isFinal: true)],
                screenshotNote: false
            )
            let system = PromptBuilder.systemPrompt(modePrompt: BuiltInModes.mode(id: "looking-for-work").prompt)
            let reply = try await Brain.complete(config: config, apiKey: ProviderSettings.apiKey, system: system, user: user)
            let seconds = Date.now.timeIntervalSince(started)
            let right = reply.contains("2")
            var text = "Answer engine (\(config.model)): replied in \(String(format: "%.1f", seconds)) s"
            if !right { text += ", but the reply did not say 2. It said: \(reply.prefix(90))" }
            lines.append(Line(ok: right, text: text))
        } catch {
            lines.append(Line(ok: false, text: "Answer engine (\(config.model)): \(error.localizedDescription)"))
        }

        // 2. The speech model.
        let kind = TranscriptionEngineKind(rawValue: UserDefaults.standard.string(forKey: "transcription.engine") ?? "parakeetUltra") ?? .parakeetUltra
        switch kind {
        case .parakeetUltra:
            do {
                try await ParakeetRuntime.shared.prepare()
                lines.append(Line(ok: true, text: "Speech model (Parakeet Ultra) is loaded"))
            } catch {
                lines.append(Line(ok: false, text: "Speech model (Parakeet Ultra) failed to load: \(error.localizedDescription)"))
            }
        case .whisper:
            let model = UserDefaults.standard.string(forKey: "transcription.whisperModel") ?? "large-v3-v20240930_626MB"
            do {
                try await WhisperRuntime.shared.prepare(model: model)
                lines.append(Line(ok: true, text: "Speech model (Whisper) is loaded"))
            } catch {
                lines.append(Line(ok: false, text: "Speech model (Whisper) failed to load: \(error.localizedDescription)"))
            }
        case .appleSpeech:
            lines.append(Line(ok: true, text: "Speech engine: Apple Speech (built in, nothing to load)"))
        }

        // 3. Permissions.
        let mic = PermissionState.microphone()
        lines.append(Line(ok: mic == "Granted", text: "Microphone: \(mic)"))
        let screen = PermissionState.screenRecordingGranted()
        lines.append(Line(ok: screen, text: "Screen Recording, needed to hear the other side: \(screen ? "Granted" : "Not granted")"))

        // 4. The Auto Answer gate.
        let gate = AutoAnswerGate.shouldAnswer("What is 1 plus 1?")
        lines.append(Line(ok: gate, text: "Auto Answer gate lets a real question through"))

        isRunning = false
    }
}
