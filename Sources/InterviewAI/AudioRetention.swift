import Foundation
import SwiftData
import InterviewAIKit

/// The retention window for saved session audio, set in Settings
/// under "Keep Session Audio For". When a window is chosen, the
/// audio of meetings older than it is deleted: the recording
/// goes, while the transcript, the summary, and everything
/// written from them stay. This is the retention idea from
/// Ashby's recording modes, where audio can be kept only as long
/// as it is needed; here it runs as a sweep at launch and
/// whenever the setting changes, so nothing has to run in the
/// background.
///
/// The window is counted from the meeting's start, not the
/// file's, because "the call from March" is how the user thinks
/// about it. Only meetings that still point at an audio file are
/// touched, and clearing the file name is the whole change: the
/// meeting keeps everything else.
enum AudioRetention {
    static let defaultsKey = "sessionAudio.retentionDays"

    /// The chosen window in days; 0 means keep forever.
    static var keepDays: Int {
        UserDefaults.standard.integer(forKey: defaultsKey)
    }

    /// Delete the audio of every meeting older than the window.
    /// A no-op when the window is "forever" or the app's model is
    /// not up yet.
    @MainActor
    static func sweep() {
        let days = keepDays
        guard days > 0, let model = AppModel.current else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let context = model.container.mainContext
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        var changed = false
        for meeting in meetings where !meeting.audioFileName.isEmpty && meeting.startedAt < cutoff {
            SessionAudioStore.delete(fileName: meeting.audioFileName)
            meeting.audioFileName = ""
            changed = true
        }
        if changed { try? context.save() }
    }
}
