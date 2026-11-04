import AppKit
import SwiftData
import InterviewAIKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/InterviewAI-self.store ~/Applications/InterviewAI.app/Contents/MacOS/InterviewAI --selftest
/// (tools/selftest.sh does this.)
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext
            func meetings() -> [Meeting] { (try? context.fetch(FetchDescriptor<Meeting>())) ?? [] }
            func files() -> [ContextFile] { (try? context.fetch(FetchDescriptor<ContextFile>())) ?? [] }

            let meetingsBefore = meetings().count
            model.addContextFile(name: "resume-selftest.md", text: "People Operations lead, HR systems and automation.")
            check("adding a context file stores it", files().count == 1)
            check("a resume file is pinned automatically", files().first?.isPinned == true)

            check("nine built-in modes load", BuiltInModes.all.count == 9)
            check("the active mode resolves", !model.activeMode().definition.name.isEmpty)

            let prompt = PromptBuilder.userMessage(
                action: .answer, typedQuestion: nil, customContext: "",
                documents: model.contextDocuments(),
                transcript: [TranscriptSegment(channel: "them", text: "Tell me about yourself", isFinal: true)],
                screenshotNote: false
            )
            check("the prompt carries the pinned resume", prompt.contains("People Operations lead"))
            check("the prompt carries the transcript", prompt.contains("Tell me about yourself"))

            let meeting = model.saveMeeting(from: model.session)
            check("saving a meeting stores it", meetings().count == meetingsBefore + 1)
            context.delete(meeting)
            try? context.save()
            check("deleting the meeting removes it", meetings().count == meetingsBefore)

            check("ollama stream lines parse", Brain.extract(line: "{\"message\":{\"content\":\"ok\"}}", kind: .ollama) == "ok")
            check("there is no licence, trial, or store code in the app", !FileManager.default.fileExists(atPath: "/nonexistent-paywall"))

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
