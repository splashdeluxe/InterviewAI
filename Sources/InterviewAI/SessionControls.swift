import AppKit
import InterviewAIKit
import SwiftUI

/// The Session Controls: what Stop opens while a session is running.
/// End saves the meeting, Pause freezes the session where it stands,
/// Delete throws it away. In quit mode the same window guards a quit:
/// the app only terminates after End or Delete, and Cancel hands the
/// quit back. Modelled on the About window's standing pattern.
struct SessionControlsView: View {
    let session: LiveSession
    let quitMode: Bool
    /// Called once with the outcome; the window closes itself first.
    /// `proceedQuit` is only meaningful in quit mode.
    let onOutcome: (_ proceedQuit: Bool) -> Void

    @State private var confirmingDelete = false
    /// Flipped on appear, so the choices can stagger in under it.
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Space.md) {
            HStack {
                Spacer()
                Button("Close", systemImage: "xmark") { onOutcome(false) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietButtonStyle())
                    .help("Back to the session")
            }
            ZStack {
                Circle()
                    .fill(Surface.inset)
                    .frame(width: 48, height: 48)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            Text("Session Controls")
                .font(.title3.weight(.semibold))
            if confirmingDelete {
                deleteConfirmation
            } else {
                choices
            }
        }
        .padding(Space.lg)
        .frame(width: 400)
        .background(Surface.panel)
    }

    /// The peak-end rule, as one line: people remember a session
    /// by its best moment and by how it ended, so while the user
    /// decides how this one ends, the line states what there is
    /// to remember it by — how long it ran, how much was heard,
    /// and whether an answer stands ready at the end.
    private var peakEndLine: String {
        let total = Int(session.duration)
        let durationText = String(format: "%02d:%02d", total / 60, total % 60)
        let answerText = session.answer.isEmpty ? "no answer yet" : "last answer ready"
        return "\(durationText) · \(session.finalSegments.count) lines · \(answerText)"
    }

    private var choices: some View {
        VStack(spacing: Space.md) {
            Text("What would you like to do with your current session?")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(peakEndLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // Staggering: the choices arrive one after another by
            // index, not all in unison. Fitts's law: every choice
            // also keeps at least the Kit's minimum hit target —
            // the End and Delete styles already clear it on their
            // padding, the Pause button's quiet style did not, so
            // its frame states the target outright below.
            VStack(spacing: Space.sm) {
                // Von Restorff: End is the one choice that looks
                // different — the only filled, ink button in the
                // list — so the choice the session is remembered
                // by is the one that stands out.
                Button {
                    session.stop(askingWhenTiny: !quitMode)
                    onOutcome(true)
                } label: {
                    Label(quitMode ? "End Session and Quit" : "End Session", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(InkButtonStyle())
                .staggered(index: 0, appeared: appeared)
                if !quitMode {
                    Button {
                        if session.isPaused {
                            session.resume()
                        } else {
                            session.pause()
                        }
                        onOutcome(false)
                    } label: {
                        Label(session.isPaused ? "Resume Session" : "Pause Session",
                              systemImage: session.isPaused ? "play.circle" : "pause.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .frame(minHeight: CGFloat(MotionSpec.minimumHitTarget))
                    .staggered(index: 1, appeared: appeared)
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(quitMode ? "Delete Session and Quit" : "Delete Session", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DeleteButtonStyle())
                .staggered(index: quitMode ? 1 : 2, appeared: appeared)
            }
        }
        .onAppear { appeared = true }
    }

    private var deleteConfirmation: some View {
        VStack(spacing: Space.md) {
            Text("Delete this session?")
                .font(.callout.weight(.semibold))
            Text("The transcript and any recording are discarded. Nothing is saved.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: Space.sm) {
                Button(role: .destructive) {
                    session.discard()
                    onOutcome(true)
                } label: {
                    Label(quitMode ? "Delete Session and Quit" : "Delete Session", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DeleteButtonStyle())
                Button("Keep Session") { confirmingDelete = false }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

/// The Delete row's soft red fill: destructive, but a choice in a
/// list, not an alarm.
private struct DeleteButtonStyle: ButtonStyle {
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

enum SessionControlsWindow {
    private static var controller: NSWindowController?
    private static var quitCompletion: ((Bool) -> Void)?
    private static var resolved = true
    private static let closeWatcher = CloseWatcher()

    private final class CloseWatcher: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            SessionControlsWindow.windowClosed()
        }
    }

    /// The window went away without a choice (its close button): in
    /// quit mode that is a Cancel, the app stays.
    fileprivate static func windowClosed() {
        guard !resolved else { return }
        resolved = true
        let completion = quitCompletion
        quitCompletion = nil
        completion?(false)
    }

    static func show(session: LiveSession, quitMode: Bool, completion: ((Bool) -> Void)? = nil) {
        quitCompletion = completion
        resolved = false
        let view = SessionControlsView(session: session, quitMode: quitMode) { proceedQuit in
            resolved = true
            let completion = quitCompletion
            quitCompletion = nil
            controller?.close()
            completion?(proceedQuit)
        }
        if let controller, let window = controller.window {
            window.contentView = NSHostingView(rootView: view)
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Session Controls"
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
}
