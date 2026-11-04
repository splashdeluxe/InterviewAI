import Foundation
import SwiftData
import InterviewAIKit

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an
/// empty store with one sample meeting and two sample context files, so
/// every page shows real content. Seed only what a person can create in
/// the app.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Meeting>())) ?? 0) == 0 else { return }

        let segments = [
            TranscriptSegment(channel: "them", text: "Thanks for joining. Can you walk me through your People Operations experience?", at: Date.now.addingTimeInterval(-1_800), isFinal: true),
            TranscriptSegment(channel: "me", text: "Of course. I lead People Operations and HR systems, most recently building AI workflows for hiring.", at: Date.now.addingTimeInterval(-1_740), isFinal: true),
            TranscriptSegment(channel: "them", text: "What is your salary expectation for this role?", at: Date.now.addingTimeInterval(-1_680), isFinal: true),
            TranscriptSegment(channel: "me", text: "Based on the scope, my target is around 95,000, and the full package matters more than one line.", at: Date.now.addingTimeInterval(-1_620), isFinal: true),
        ]
        let meeting = Meeting(title: "Looking for Work · Sample Interview", modeID: "looking-for-work", modeName: "Looking for Work")
        meeting.startedAt = Date.now.addingTimeInterval(-3_600)
        meeting.durationSeconds = 1_740
        meeting.transcriptJSON = TranscriptSegment.encode(segments)
        meeting.notes = "They care about HR systems depth. Send the automation case study after the call."
        meeting.summary = "Summary: a first interview covering People Operations scope, HR systems, and salary.\nDecisions:\n- None yet.\nAction items:\n- Send the automation case study."
        meeting.followUp = "Thanks for the conversation today. As promised, I am sending the automation case study we discussed. Happy to go deeper on the HR systems side in the next round."
        context.insert(meeting)
        model.selectedMeeting = meeting.id

        context.insert(ContextFile(
            name: "resume-sample.md", kind: "resume",
            text: "Sample resume. People Operations lead. I run HR systems, hiring workflows, and AI automation for People teams. Recent work: automated screening workflows, cut time-to-shortlist, introduced structured interviews.",
            isPinned: true
        ))
        context.insert(ContextFile(
            name: "job-sample.md", kind: "job",
            text: "Sample job description. Head of People Operations, remote Europe. Own HR systems, people processes, and a small team. Salary band 90,000 to 105,000.",
            isPinned: true
        ))
        try? context.save()
    }
}
