import AppKit
import InterviewAIKit
import SwiftUI

/// One line of the keyboard map: the keys and what they do.
struct ShortcutRow: Identifiable {
    let keys: String
    let action: String
    var id: String { keys }
}

/// The keyboard map in one place: the corner menu shows it as a
/// submenu, and Command-slash opens it as a window. Every other
/// surface points here instead of keeping its own copy. The three
/// global hotkeys, the seven answer actions, and the two menu keys.
struct ShortcutsView: View {
    static var rows: [ShortcutRow] {
        [
            ShortcutRow(keys: "⌘ ⇧ L", action: "Start or stop listening"),
            ShortcutRow(keys: "⌘ ⇧ H", action: "Show or hide the overlay"),
            ShortcutRow(keys: "⌘ ⇧ S", action: "Attach the front window as a screenshot to the next answer"),
            ShortcutRow(keys: "⌘ 1 … ⌘ 7", action: "Answer actions: " + AnswerAction.allCases.map(\.title).joined(separator: ", ")),
            ShortcutRow(keys: "⌘ ,", action: "Settings"),
            ShortcutRow(keys: "⌘ /", action: "This list"),
        ]
    }

    private var rows: [ShortcutRow] { Self.rows }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Keyboard Shortcuts")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: Space.lg) {
                        Text(row.keys)
                            .font(.callout.weight(.medium))
                            .frame(width: 92, alignment: .leading)
                        Text(row.action)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Space.sm)
                    if index < rows.count - 1 {
                        Rectangle().fill(Surface.hairline).frame(height: 1)
                    }
                }
            }
            Text("The first three work everywhere on this Mac, even while another app is in front. The answer actions fire on the current session.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.xl)
        .frame(width: 460)
        .background(Surface.canvas)
    }
}

/// One Shortcuts window, reused, like the About window: a plain AppKit
/// window the app menu and the corner menu both open.
@MainActor
enum ShortcutsWindow {
    private static var controller: NSWindowController?

    static func show() {
        if let controller {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Keyboard Shortcuts"
        window.contentView = NSHostingView(rootView: ShortcutsView())
        window.isReleasedWhenClosed = false
        window.center()
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate()
        sizeWindowToContent(window)
    }
}
