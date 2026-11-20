import Foundation
import InterviewAIKit

/// Write Scorecard for a saved meeting: the deep model reads the
/// finished transcript in chunks, playing the interviewer, and
/// collects the points that side would file, then a merge pass
/// dedupes them and writes the overall read. Every point is
/// fenced against the real call before it is stored (see
/// ScorecardParsing): a point resting on a moment outside the
/// call is dropped, so the card can judge, but it cannot invent
/// the moment it judges from. The original transcript is only
/// read, never touched.
///
/// The run reports its progress chunk by chunk plus the merge,
/// and returns its task, like Find Questions: the meeting page
/// shows "2 of 5" and offers Cancel. Cancelling stops between
/// steps and reaches the in-flight request through the Deep
/// queue; nothing is saved.
enum ScorecardWriter {
    @discardableResult
    static func write(meeting: Meeting,
                      onProgress: @escaping @MainActor (Int, Int) -> Void,
                      onDone: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never> {
        let segments = meeting.segments.filter(\.isFinal)
        guard !segments.isEmpty else {
            Task { @MainActor in onDone(false) }
            return Task {}
        }

        // The chunk text marks every line with its moment as a
        // plain [seconds] number, copied from the segment itself.
        // The scorecard prompt tells the model to copy that number
        // as a point's timestamp; a minutes:seconds marker invites
        // it to hand back the minute alone, which the range fence
        // cannot tell from a real early moment.
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
            var probed: [ScorecardPoint] = []
            var evidence: [ScorecardPoint] = []
            var gaps: [ScorecardPoint] = []
            for (index, chunk) in chunks.enumerated() {
                if Task.isCancelled { return }
                await MainActor.run { onProgress(index, totalSteps) }
                let outcome = try? await DeepWork.complete(
                    system: ScorecardPrompts.system + WritingInstructions.promptSuffix,
                    user: ScorecardPrompts.user(transcript: chunk),
                    maxTokens: 1600
                )
                if Task.isCancelled { return }
                guard let outcome, !outcome.text.isEmpty else {
                    await MainActor.run { onDone(false) }
                    return
                }
                // A chunk that parses to nothing contributes
                // nothing; it does not fail the run.
                if let partial = ScorecardParsing.parse(outcome.text, maxSeconds: maxSeconds) {
                    probed += partial.probed
                    evidence += partial.evidence
                    gaps += partial.gaps
                }
                await MainActor.run { onProgress(index + 1, totalSteps) }
            }
            if Task.isCancelled { return }
            let mergeOutcome = try? await DeepWork.complete(
                system: ScorecardMergePrompts.system + WritingInstructions.promptSuffix,
                user: ScorecardMergePrompts.user(
                    title: title,
                    modeName: modeName,
                    pointsJSON: ScorecardParsing.encodePoints(probed: probed, evidence: evidence, gaps: gaps)
                ),
                maxTokens: 2000
            )
            if Task.isCancelled { return }
            guard let mergeOutcome, !mergeOutcome.text.isEmpty,
                  let card = ScorecardParsing.parse(mergeOutcome.text, maxSeconds: maxSeconds) else {
                await MainActor.run { onDone(false) }
                return
            }
            meeting.scorecardJSON = InterviewScorecard.encode(card)
            meeting.scorecardWritten = true
            try? meeting.modelContext?.save()
            await MainActor.run { onDone(true) }
        }
    }
}
