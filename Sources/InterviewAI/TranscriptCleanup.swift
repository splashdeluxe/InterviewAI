import Foundation
import InterviewAIKit

/// Clean Transcript for a saved meeting: the deep model rewrites
/// the transcript into a polished copy, in chunks a local model
/// can hold, and the result is stored beside the original, which
/// is never touched. Long transcripts are chunked on segment
/// boundaries at about 6,000 characters of plain text per call.
enum TranscriptCleaner {
    static func clean(meeting: Meeting, onDone: @escaping @MainActor (Bool) -> Void) {
        let segments = meeting.segments.filter(\.isFinal)
        guard !segments.isEmpty else {
            Task { @MainActor in onDone(false) }
            return
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

        Task {
            var cleaned: [TranscriptSegment] = []
            for chunk in chunks {
                let outcome = try? await DeepWork.complete(
                    system: CleanTranscriptPrompts.system,
                    user: CleanTranscriptPrompts.user(
                        confirmedNames: names, attendees: attendees,
                        summary: summary, transcript: chunk
                    ),
                    maxTokens: 2400
                )
                guard let outcome, !outcome.text.isEmpty else {
                    await MainActor.run { onDone(false) }
                    return
                }
                cleaned += CleanedTranscript.segments(from: outcome.text, myName: myName)
            }
            guard !cleaned.isEmpty else {
                await MainActor.run { onDone(false) }
                return
            }
            meeting.cleanedTranscriptJSON = TranscriptSegment.encode(cleaned)
            try? meeting.modelContext?.save()
            await MainActor.run { onDone(true) }
        }
    }
}
