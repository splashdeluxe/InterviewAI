import AppKit
import InterviewAIKit
import SwiftData
import SwiftUI

// InterviewAI
//   InterviewAI                      the app
//   APP_STORE=<file> InterviewAI     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> InterviewAI   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 InterviewAI           fill an empty /tmp store with sample data (tools/snap.sh)
//   InterviewAI --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> InterviewAI      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 InterviewAI           draw the 8 pt grid and the layout probes over the window

@main
struct InterviewAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("InterviewAI", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 900, minHeight: 560)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About InterviewAI") { AboutWindow.show() }
                Button("What's New") { AboutWindow.show(.whatsNew) }
                Button("Support") { AboutWindow.show(.support) }
                Button("Check for Updates…") {
                    AboutWindow.show()
                    Task { await UpdateChecker.shared.check() }
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Keyboard Shortcuts") { ShortcutsWindow.show() }
                    .keyboardShortcut("/", modifiers: .command)
            }
            // No .appSettings group here: the Settings scene already puts
            // one Settings… item in the app menu, and a second one from a
            // command group would only duplicate it. SettingsLink lives
            // in the menu bar extra instead.
            SidebarCommands()
            ToolbarCommands()
            CommandMenu("Interview") {
                Button(model.session.isListening ? "Stop Listening" : "Start Listening") {
                    model.session.toggle()
                }
                Button(model.overlay.isShown ? "Hide Overlay" : "Show Overlay") {
                    model.overlay.toggle()
                }
                Divider()
                ForEach(Array(AnswerAction.allCases.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { model.session.runAction(action, typedQuestion: nil) }
                }
                Divider()
                Button("Screenshot the Front Window") { model.session.captureScreenshot() }
            }
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra("InterviewAI", systemImage: "waveform.badge.mic", isInserted: Binding(
            get: { model.showMenuBarIcon },
            set: { model.showMenuBarIcon = $0 }
        )) {
            Text(model.session.isListening ? "Listening" : "Idle")
            Button(model.session.isListening ? "Stop Listening" : "Start Listening") {
                model.session.toggle()
            }
            Button(model.overlay.isShown ? "Hide Overlay" : "Show Overlay") {
                model.overlay.toggle()
            }
            Divider()
            SettingsLink { Text("Settings…") }
            Button("About InterviewAI") { AboutWindow.show() }
            Button("Check for Updates…") {
                AboutWindow.show()
                Task { await UpdateChecker.shared.check() }
            }
            Divider()
            Button("Quit InterviewAI") { NSApp.terminate(nil) }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The Show in Dock setting from the last run. Unset means shown.
        let showInDock = UserDefaults.standard.object(forKey: "general.showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        NSApp.activate()
        Task { @MainActor in
            WhatsNewLaunch.run()
            UpdateChecker.shared.checkIfStale()
            // Nils's call (2026-11-12): the Support sheet stays live but
            // rare, not on every open. It shows at most once every 14
            // days, and the stamp is written only when it actually
            // shows. Skipped for the dev tools (snapshots, seed data,
            // store overrides), which launch the app with APP_* env set.
            let env = ProcessInfo.processInfo.environment
            if env["APP_SNAPSHOT"] == nil, env["APP_SEED"] == nil, env["APP_STORE"] == nil {
                let defaults = UserDefaults.standard
                let lastShown = defaults.double(forKey: "support.lastShownAt")
                let fourteenDays: TimeInterval = 14 * 24 * 60 * 60
                if lastShown == 0 || Date().timeIntervalSince1970 - lastShown >= fourteenDays {
                    defaults.set(Date().timeIntervalSince1970, forKey: "support.lastShownAt")
                    AboutWindow.show(.support)
                }
            }
        }
    }

    // Stay alive in the menu bar when the main window closes. The
    // overlay, the hotkeys, and a running session all outlive the
    // window; quitting is the Quit command or Command-Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/InterviewAI/InterviewAI.store
enum Store {
    /// True when APP_STORE points at a scratch store in /tmp (tests,
    /// snapshots, seed data). The dev tools' messages promise /tmp,
    /// so the check enforces /tmp: any other override is ignored and
    /// the real store opens instead.
    static var isOverridden: Bool { overrideURL != nil }

    private static var overrideURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        // macOS 27 canonicalises /private/tmp back to /tmp in compiled
        // processes, so accept both spellings, raw and resolved. Checking
        // only the /private/tmp form made every override refuse.
        func inTmp(_ p: String) -> Bool {
            p == "/tmp" || p == "/private/tmp" || p.hasPrefix("/tmp/") || p.hasPrefix("/private/tmp/")
        }
        guard inTmp(path) || inTmp(resolved) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static var url: URL {
        if let overrideURL {
            return overrideURL
        }
        let dir = URL.applicationSupportDirectory.appending(path: "InterviewAI", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "InterviewAI.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Meeting.self, ContextFile.self, CustomMode.self, IntelligenceDoc.self,
                configurations: ModelConfiguration(url: url)
            )
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
