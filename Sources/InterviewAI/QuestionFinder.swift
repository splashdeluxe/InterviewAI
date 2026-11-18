import Foundation
import InterviewAIKit

/// Find Questions for a saved meeting: the deep model reads the
/// finished transcript in chunks and returns the questions the
/// other side asked, each with the answer the user gave. Every
/// pair is fenced against the real transcript before it is
/// stored (see QuestionExtraction), so an invented question or a
/// polished answer never reaches the meeting. The original
/// transcript is only read, never touched.
///
/// A long meeting is many chunks, so the run reports its
/// progress chunk by chunk and returns its task, like Clean
/// Transcript: the meeting page shows "2 of 5" and offers
/// Cancel. Cancelling stops between chunks and reaches the
/// in-flight request through the Deep queue; nothing is saved.
enum QuestionFinder {
    @discardableResult
    static func find(meeting: Meeting,
                     onProgress: @escaping @MainActor (Int, Int) -> Void,
                     onDone: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never> {
        let segments = meeting.segments.filter(\.isFinal)
        guard !segments.isEmpty else {
            Task { @MainActor in onDone(false) }
            return Task {}
        }

        var chunks: [String] = []
        var current: [TranscriptSegment] = []
        var length = 0
        for segment in segments {
            let lineLength = segment.speakerName.count + segment.text.count + 2
            if length + lineLength > 6000, !current.isEmpty {
                chunks.append(TranscriptSegment.plainText(current, includeTimestamps: true))
                current = []
                length = 0
            }
            current.append(segment)
            length += lineLength
        }
        if !current.isEmpty { chunks.append(TranscriptSegment.plainText(current, includeTimestamps: true)) }

        return Task {
            var pairs: [QuestionPair] = []
            for (index, chunk) in chunks.enumerated() {
                if Task.isCancelled { return }
                await MainActor.run { onProgress(index, chunks.count) }
                let outcome = try? await DeepWork.complete(
                    system: QuestionPrompts.system,
                    user: QuestionPrompts.user(transcript: chunk),
                    maxTokens: 2400
                )
                if Task.isCancelled { return }
                guard let outcome, !outcome.text.isEmpty else {
                    await MainActor.run { onDone(false) }
                    return
                }
                pairs += QuestionExtraction.pairs(from: outcome.text, segments: segments)
                await MainActor.run { onProgress(index + 1, chunks.count) }
            }
            if Task.isCancelled { return }
            var seen: Set<String> = []
            pairs = pairs
                .sorted { $0.atSeconds < $1.atSeconds }
                .filter { seen.insert("\($0.atSeconds)|\($0.question)").inserted }
            meeting.questionsJSON = QuestionPair.encode(pairs)
            meeting.questionsExtracted = true
            try? meeting.modelContext?.save()
            await MainActor.run { onDone(true) }
        }
    }
}
