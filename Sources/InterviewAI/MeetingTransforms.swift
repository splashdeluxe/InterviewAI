import Foundation
import InterviewAIKit

/// Running one Create-tab transform on a saved meeting: the deep
/// model carries out the transform's instruction on the text it is
/// given — the Clean Transcript when the meeting has one, the
/// original transcript otherwise, or the meeting's summary for the
/// translate and tone transforms — under the TransformPrompt fence,
/// and the result is saved on the meeting. A transform adds a
/// result; it never overwrites the summary, the follow-up, or an
/// older result.
///
/// The run returns its task, like Find Questions and Clean
/// Transcript: the meeting page shows it running and offers Cancel.
/// Cancelling reaches the in-flight request through the Deep queue
/// and saves nothing, and a failed or empty run saves nothing
/// either; both are reported through onDone, never hidden.
enum MeetingTransforms {
    @discardableResult
    static func run(meeting: Meeting, definition: TransformDefinition, inputText: String, inputLabel: String, source: TransformSource,
                    onDone: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never> {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Task { @MainActor in onDone(false) }
            return Task {}
        }
        let attendees = meeting.attendees.isEmpty ? [] : meeting.attendees.components(separatedBy: ", ")
        let user = TransformPrompt.userMessage(
            definition: definition, inputLabel: inputLabel, inputText: inputText,
            title: meeting.title, attendees: attendees
        )
        return Task {
            let outcome = try? await DeepWork.complete(
                system: TransformPrompt.system,
                user: user,
                maxTokens: 1200
            )
            // A cancel is not a failure: the page already reset its
            // running state when the user tapped Cancel, so a
            // cancelled run ends quietly and saves nothing, the
            // same way Find Questions ends.
            if Task.isCancelled { return }
            guard let outcome else {
                await MainActor.run { onDone(false) }
                return
            }
            let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                await MainActor.run { onDone(false) }
                return
            }
            var results = meeting.transformResults
            results.append(TransformResult(
                name: definition.name, prompt: definition.instruction,
                text: text, source: source
            ))
            meeting.transformsJSON = TransformResult.encode(results)
            try? meeting.modelContext?.save()
            await MainActor.run { onDone(true) }
        }
    }
}
