import AppKit
import SwiftUI

/// The keyboard map in one place, opened from the corner menu or with
/// Command-slash: the three global hotkeys, the seven answer actions,
/// and the two menu keys.
struct ShortcutsView: View {
    private let rows: [(keys: String, action: String)] = [
        ("⌘ ⇧ L", "Start or stop listening"),
        ("⌘ ⇧ H", "Show or hide the overlay"),
        ("⌘ ⇧ S", "Attach the front window as a screenshot to the next answer"),
        ("⌘ 1 … ⌘ 7", "Answer actions: What Should I Say, Clarify, Recap, Follow-Up, Answer, Code Hint, Brainstorm"),
        ("⌘ ,", "Settings"),
        ("⌘ /", "This list"),
    ]

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
