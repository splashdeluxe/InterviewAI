import AppKit
import SwiftUI
import InterviewAIKit

/// Auto-start, the app side: a slow watch over the calendar, and
/// when the Kit's `AutoStart` decision finds a video call that has
/// begun, a small panel appears at the bottom right of the screen
/// with a ten-second countdown. When the countdown runs out,
/// listening starts for that event, with its title and people
/// already filled in by the normal event start. "Start Now" skips
/// the wait; the close button dismisses the event for good.
///
/// The guardrails live here and in the Kit together: the feature
/// is off until the user turns it on in Settings, an event fires
/// at most once ever (fired and dismissed ids are remembered in
/// the defaults until the event ends), nothing fires while a
/// session is running, and the countdown cancels itself if a
/// session starts another way or the event ends first.
@Observable
final class AutoStartController {
    @ObservationIgnored weak var model: AppModel?

    /// The Settings switch, General → Meeting Detection.
    static let enabledKey = "session.autoStart"
    static let countdownSeconds = 10

    /// The event currently being offered, and the seconds left
    /// before it starts on its own. The panel reads both.
    var pendingEvent: UpcomingEvent?
    var secondsLeft = 0

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    private static let handledKey = "session.autoStart.handled"

    /// Event ids already fired for or dismissed, mapped to the
    /// event's end as a timestamp, so a relaunch mid-call does not
    /// offer the same call a second time. Entries are pruned once
    /// their event is over.
    private var handled: [String: TimeInterval] {
        get { UserDefaults.standard.dictionary(forKey: Self.handledKey) as? [String: TimeInterval] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.handledKey) }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Begin watching. Called once from the model's init; the
    /// watch itself is a light check every twenty seconds, and it
    /// does nothing at all while the setting is off.
    func start() {
        guard watchTask == nil else { return }
        watchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    @MainActor
    private func check() {
        guard isEnabled, pendingEvent == nil, let model else { return }
        let now = Date.now
        var remembered = handled
        remembered = remembered.filter { $0.value > now.timeIntervalSince1970 }
        if remembered != handled { handled = remembered }
        let events = CalendarService.events(
            from: now.addingTimeInterval(-6 * 60 * 60),
            to: now.addingTimeInterval(60 * 60)
        )
        guard let event = AutoStart.candidate(
            events: events, now: now,
            handled: Set(remembered.keys),
            isListening: model.session.isListening
        ) else { return }
        offer(event)
    }

    @MainActor
    private func offer(_ event: UpcomingEvent) {
        pendingEvent = event
        secondsLeft = Self.countdownSeconds
        showPanel()
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let pending = self.pendingEvent else { return }
                // The offer dies quietly when the world moves on:
                // the feature was switched off, a session started
                // another way, or the event ended during the wait.
                guard self.isEnabled,
                      self.model?.session.isListening == false,
                      Date.now < pending.end else {
                    self.cancelOffer()
                    return
                }
                self.secondsLeft -= 1
                if self.secondsLeft <= 0 {
                    self.fire()
                    return
                }
            }
        }
    }

    /// The countdown ran out, or the user tapped Start Now: mark
    /// the event handled and start listening for it.
    @MainActor
    func fire() {
        guard let event = pendingEvent, let model else { return }
        markHandled(event)
        clearOffer()
        model.session.start(event: event)
    }

    /// The close button: this event never offers itself again.
    @MainActor
    func dismiss() {
        guard let event = pendingEvent else { return }
        markHandled(event)
        clearOffer()
    }

    @MainActor
    private func cancelOffer() {
        clearOffer()
    }

    @MainActor
    private func clearOffer() {
        countdownTask?.cancel()
        countdownTask = nil
        pendingEvent = nil
        secondsLeft = 0
        panel?.orderOut(nil)
    }

    private func markHandled(_ event: UpcomingEvent) {
        var remembered = handled
        remembered[event.id] = event.end.timeIntervalSince1970
        handled = remembered
    }

    // MARK: Panel

    @MainActor
    private func showPanel() {
        guard let model else { return }
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 392, height: 92),
                styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                backing: .buffered, defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovable = false
            panel.contentView = NSHostingView(rootView: AnyView(AutoStartPillView().environment(model).environment(self)))
            self.panel = panel
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: frame.maxX - 392 - Space.lg, y: frame.minY + Space.lg))
        }
        panel?.orderFrontRegardless()
    }
}

/// The countdown card itself: what was detected, how long is left,
/// and the two ways out, start now or never for this event.
struct AutoStartPillView: View {
    @Environment(AppModel.self) private var model
    @Environment(AutoStartController.self) private var autoStart

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "video.fill")
                .font(.title3)
                .foregroundStyle(Surface.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting detected")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(autoStart.pendingEvent?.title ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Listening starts in \(autoStart.secondsLeft) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: Space.sm)
            Button("Start Now") { autoStart.fire() }
                .buttonStyle(InkButtonStyle())
            Button { autoStart.dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(QuietButtonStyle())
            .help("Do not start for this meeting")
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Surface.panel, in: RoundedRectangle(cornerRadius: Radius.overlay))
    }
}
