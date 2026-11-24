import AppKit
import SwiftUI

/// The "Started by mistake?" prompt: a session that stopped
/// with only a few words captured waits on this window before
/// anything is saved. Keep saves it like any ended session,
/// Discard throws it away. Closing the window counts as Keep:
/// an unanswered prompt never deletes a recording. Modelled
/// on the Session Controls window's standing pattern.
struct MistakePromptView: View {
    let session: LiveSession
    let wordCount: Int
    /// Called once with the outcome; the window closes itself first.
    let onOutcome: () -> Void

    var body: some View {
        VStack(spacing: Space.md) {
            HStack {
                Spacer()
                Button("Close", systemImage: "xmark") { answer(keep: true) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietButtonStyle())
                    .help("Keep the meeting")
            }
            ZStack {
                Circle()
                    .fill(Surface.inset)
                    .frame(width: 48, height: 48)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
            }
            Text("Started by mistake?")
                .font(.title3.weight(.semibold))
            Text("Only \(wordCount) \(wordCount == 1 ? "word was" : "words were") captured. Keep this meeting or discard it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.sm) {
                Button(role: .destructive) { answer(keep: false) } label: {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MistakeDiscardButtonStyle())
                Button { answer(keep: true) } label: {
                    Text("Keep")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(InkButtonStyle())
            }
        }
        .padding(Space.lg)
        .frame(width: 400)
        .background(Surface.panel)
    }

    private func answer(keep: Bool) {
        if keep {
            session.keepPendingEnd()
        } else {
            session.discardPendingEnd()
        }
        onOutcome()
    }
}

/// The Discard choice's soft red fill, the Session Controls
/// Delete row's look: destructive, but a choice in a row,
/// not an alarm.
private struct MistakeDiscardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.red)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Color.red.opacity(configuration.isPressed ? 0.16 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

enum MistakePromptWindow {
    private static var controller: NSWindowController?
    private static var pendingSession: LiveSession?
    private static var resolved = true
    private static let closeWatcher = CloseWatcher()

    private final class CloseWatcher: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MistakePromptWindow.windowClosed()
        }
    }

    /// The window went away without a button (its close
    /// button): that counts as Keep, never as Discard.
    fileprivate static func windowClosed() {
        guard !resolved else { return }
        resolved = true
        let session = pendingSession
        pendingSession = nil
        session?.keepPendingEnd()
    }

    static func show(session: LiveSession, wordCount: Int) {
        pendingSession = session
        resolved = false
        let view = MistakePromptView(session: session, wordCount: wordCount) {
            resolved = true
            pendingSession = nil
            controller?.close()
        }
        if let controller, let window = controller.window {
            window.contentView = NSHostingView(rootView: view)
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Started by mistake?"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = closeWatcher
        window.center()
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate()
    }

    /// Close the prompt from the session's side: starting a
    /// new session settles the held one as Keep, and the
    /// window follows it down.
    static func dismiss() {
        guard !resolved else { return }
        resolved = true
        pendingSession = nil
        controller?.close()
    }
}
