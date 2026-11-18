import Foundation
import InterviewAIKit

/// Clean Transcript for a saved meeting: the deep model rewrites
/// the transcript into a polished copy, in chunks a local model
/// can hold, and the result is stored beside the original, which
/// is never touched. Long transcripts are chunked on segment
/// boundaries at about 6,000 characters of plain text per call.
///
/// A long meeting is many chunks, and each chunk is a full model
/// answer, so a clean can take minutes on a local model. The run
/// therefore reports its progress chunk by chunk and returns its
/// task, so the meeting page can show "3 of 9" and offer Cancel.
/// Cancelling stops between chunks and reaches the in-flight
/// request through the Deep queue; nothing is saved, and the
/// original transcript is untouched either way.
enum TranscriptCleaner {
    @discardableResult
    static func clean(meeting: Meeting,
                      onProgress: @escaping @MainActor (Int, Int) -> Void,
                      onDone: @escaping @MainActor (Bool) -> Void) -> Task<Void, Never> {
        let segments = meeting.segments.filter(\.isFinal)
        guard !segments.isEmpty else {
            Task { @MainActor in onDone(false) }
            return Task {}
        }
        let names = SpeakerNames.distinctNames(segments: meeting.segments)
        let attendees = meeting.attendees.isEmpty ? [] : meeting.attendees.components(separatedBy: ", ")
        let summary = meeting.summary
        let myName = LiveSession.myNameSetting

        var chunks: [String] = []
        var current: [TranscriptSegment] = []
        var length = 0
        for segment in segments {
            let lineLength = segment.speakerName.count + segment.text.count + 2
            if length + lineLength > 6000, !current.isEmpty {
                chunks.append(TranscriptSegment.plainText(current))
                current = []
                length = 0
            }
            current.append(segment)
            length += lineLength
        }
        if !current.isEmpty { chunks.append(TranscriptSegment.plainText(current)) }

        return Task {
            var cleaned: [TranscriptSegment] = []
            for (index, chunk) in chunks.enumerated() {
                if Task.isCancelled { return }
                await MainActor.run { onProgress(index, chunks.count) }
                let outcome = try? await DeepWork.complete(
                    system: CleanTranscriptPrompts.system,
                    user: CleanTranscriptPrompts.user(
                        confirmedNames: names, attendees: attendees,
                        summary: summary, transcript: chunk
                    ),
                    maxTokens: 2400
                )
                if Task.isCancelled { return }
                guard let outcome, !outcome.text.isEmpty else {
                    await MainActor.run { onDone(false) }
                    return
                }
                cleaned += CleanedTranscript.segments(from: outcome.text, myName: myName)
                await MainActor.run { onProgress(index + 1, chunks.count) }
            }
            guard !cleaned.isEmpty, !Task.isCancelled else {
                if !Task.isCancelled { await MainActor.run { onDone(false) } }
                return
            }
            meeting.cleanedTranscriptJSON = TranscriptSegment.encode(cleaned)
            try? meeting.modelContext?.save()
            await MainActor.run { onDone(true) }
        }
    }
}
