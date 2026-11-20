import Foundation
import InterviewAIKit

/// Find Themes for a saved meeting: the deep model reads the
/// finished transcript in chunks and collects the topics each part
/// worked on, then a merge pass pools them into the call's final
/// themes, each with the moments it came up. The themes are
/// fenced against the real call before they are stored (see
/// ThemeParsing): a theme resting on a moment outside the call is
/// dropped whole, so the list can summarise, but it cannot invent
/// a topic or a moment. The original transcript is only read,
/// never touched.
///
/// The run reports its progress chunk by chunk plus the merge,
/// and returns its task, like Find Questions and Write Scorecard:
/// the meeting page shows "2 of 5" and offers Cancel. Cancelling
/// stops between steps and reaches the in-flight request through
/// the Deep queue; nothing is saved.
enum ThemeFinder {
    @discardableResult
    static func find(meeting: Meeting,
                     onProgress: @escaping @MainActor (Int, Int) -> Void,
                     onDone: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never> {
        let segments = meeting.segments.filter(\.isFinal)
        guard !segments.isEmpty else {
            Task { @MainActor in onDone(false) }
            return Task {}
        }

        // The chunk text marks every line with its moment as a
        // plain [seconds] number, copied from the segment itself,
        // the same marking Write Scorecard uses: the theme prompt
        // tells the model to copy that number as a theme's moment,
        // and a minutes:seconds marker invites it to hand back the
        // minute alone, which the range fence cannot tell from a
        // real early moment.
        let firstAt = segments[0].at
        func markedLine(_ segment: TranscriptSegment) -> String {
            let seconds = segment.startOffset ?? segment.at.timeIntervalSince(firstAt)
            return "[\(Int(seconds.rounded()))] \(segment.speakerName): \(segment.text)"
        }

        var chunks: [String] = []
        var current: [String] = []
        var length = 0
        for segment in segments {
            let line = markedLine(segment)
            if length + line.count > 6000, !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = []
                length = 0
            }
            current.append(line)
            length += line.count
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }

        let title = meeting.title
        let modeName = meeting.modeName
        let maxSeconds = meeting.durationSeconds
        // The merge is one more step after the chunks.
        let totalSteps = chunks.count + 1

        return Task {
            var candidates: [MeetingTheme] = []
            for (index, chunk) in chunks.enumerated() {
                if Task.isCancelled { return }
                await MainActor.run { onProgress(index, totalSteps) }
                let outcome = try? await DeepWork.complete(
                    system: ThemePrompts.system,
                    user: ThemePrompts.user(transcript: chunk),
                    maxTokens: 1600
                )
                if Task.isCancelled { return }
                guard let outcome, !outcome.text.isEmpty else {
                    await MainActor.run { onDone(false) }
                    return
                }
                // A chunk that parses to nothing contributes
                // nothing; it does not fail the run.
                if let partial = ThemeParsing.parse(outcome.text, maxSeconds: maxSeconds) {
                    candidates += partial
                }
                await MainActor.run { onProgress(index + 1, totalSteps) }
            }
            if Task.isCancelled { return }
            let mergeOutcome = try? await DeepWork.complete(
                system: ThemeMergePrompts.system,
                user: ThemeMergePrompts.user(
                    title: title,
                    modeName: modeName,
                    themesJSON: ThemeParsing.encodeThemes(candidates)
                ),
                maxTokens: 2600
            )
            if Task.isCancelled { return }
            guard let mergeOutcome, !mergeOutcome.text.isEmpty,
                  let themes = ThemeParsing.parse(mergeOutcome.text, maxSeconds: maxSeconds) else {
                await MainActor.run { onDone(false) }
                return
            }
            meeting.themesJSON = MeetingTheme.encode(themes)
            meeting.themesExtracted = true
            try? meeting.modelContext?.save()
            await MainActor.run { onDone(true) }
        }
    }
}
