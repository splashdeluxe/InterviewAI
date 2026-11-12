import AppKit
import Carbon
import QuartzCore
import SwiftUI
import InterviewAIKit

/// The floating panel over the call window. Non-activating, so the call
/// app keeps focus while the user reads and clicks actions here.
/// Borderless on purpose: the system title bar gave the panel a second,
/// mismatched chrome (and traffic lights that did nothing useful on a
/// panel), so the view draws the whole surface itself: one thick
/// material card with a large continuous corner and a bright top edge,
/// the way Apple's own floating panels read. Dragging the header moves
/// the panel (see installDragMonitor for how, and why it took three
/// rounds).
@Observable
final class OverlayController {
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var expandedHeight: CGFloat = 520
    @ObservationIgnored private var dragMonitors: [Any] = []
    @ObservationIgnored private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    var isShown = false
    var isCollapsed = false

    /// Header row plus the view's vertical padding: the whole panel
    /// when collapsed.
    static let collapsedHeight: CGFloat = 58

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard let model else { return }
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.borderless, .resizable, .nonactivatingPanel, .utilityWindow],
                backing: .buffered, defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 400, height: Self.collapsedHeight)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            // The drag monitor below is the one moving mechanism;
            // the panel's own movable flags stay off so nothing
            // competes with it.
            panel.isMovable = false
            panel.contentView = NSHostingView(rootView: AnyView(OverlayView().environment(model)))
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.maxX - 580, y: frame.maxY - 540))
            }
            self.panel = panel
            installDragMonitor()
        }
        // The opacity the user set in Settings, General. Unset means 1.
        let stored = UserDefaults.standard.object(forKey: "overlay.opacity") as? Double
        panel?.alphaValue = CGFloat(stored ?? 1.0)
        panel?.orderFrontRegardless()
        isShown = true
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
    }

    /// Dragging the overlay, round 3 (issue #3). Rounds 1 and 2 both
    /// died on event delivery inside this non-activating panel: a
    /// SwiftUI DragGesture never tracked, and an AppKit drag view's
    /// performDrag never fired. The buttons always worked, the drag
    /// never did. So round 3 does not ask any view for the events at
    /// all: a local event monitor sees every left-mouse-down in the
    /// app before dispatch. A press in the panel's header band that
    /// does not land on a control starts a drag; from there the
    /// monitor moves the window by the pointer's screen-space delta
    /// until the mouse comes up. 1:1, grab point preserved.
    private func installDragMonitor() {
        guard dragMonitors.isEmpty else { return }
        let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel,
                  let content = panel.contentView else { return event }
            let point = event.locationInWindow
            // A press on a control keeps its click: walk the hit
            // chain and stand down if any view in it is a control.
            if let hit = content.hitTest(point) {
                var view: NSView? = hit
                while let current = view {
                    if current is NSControl { return event }
                    view = current.superview
                }
            }
            // The header's buttons are SwiftUI views, invisible to
            // that walk, so the view reports their frames itself
            // (round 4: round 3's drag worked, but it swallowed
            // the header buttons' clicks as drags). A press on or
            // near a reported frame is a click, never a drag.
            let height = content.frame.height
            let exclusions = OverlayDragExclusions.shared.appKitRects(contentHeight: height)
            guard PanelDrag.shouldStartDrag(point: point, contentHeight: height, exclusions: exclusions) else { return event }
            self.dragStart = (mouse: NSEvent.mouseLocation, origin: panel.frame.origin)
            return nil
        }
        let drag = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let start = self.dragStart, let panel = self.panel else { return event }
            if event.type == .leftMouseUp {
                self.dragStart = nil
                return nil
            }
            panel.setFrameOrigin(PanelDrag.movedOrigin(
                startOrigin: start.origin, startMouse: start.mouse, mouse: NSEvent.mouseLocation
            ))
            return nil
        }
        dragMonitors = [down, drag].compactMap { $0 }
    }

    /// Collapse to the header bar, or back to the remembered height.
    /// The top edge stays put; the panel grows and shrinks downward.
    /// Animated with a short ease, unless the system asks for
    /// reduced motion, in which case the frame just lands.
    func toggleCollapse() {
        guard let panel else { return }
        var frame = panel.frame
        if isCollapsed {
            frame.origin.y -= expandedHeight - frame.height
            frame.size.height = expandedHeight
            panel.minSize = NSSize(width: 400, height: 320)
            isCollapsed = false
        } else {
            expandedHeight = frame.height
            frame.origin.y += frame.height - Self.collapsedHeight
            frame.size.height = Self.collapsedHeight
            panel.minSize = NSSize(width: 400, height: Self.collapsedHeight)
            isCollapsed = true
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                // Strong ease-in-out (Emil Kowalski's curve), not
                // the built-in: the stock curve is too weak at the
                // start, which is the moment the eye is watching.
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
}

/// The frames of the overlay header's buttons, reported by the
/// view itself. The drag monitor cannot find these buttons in
/// the AppKit hit chain (SwiftUI buttons are not NSControls), so
/// the view measures them and the monitor stands down on any
/// press that lands on one. Frames are stored in SwiftUI global
/// coordinates (top-left origin); the monitor converts.
final class OverlayDragExclusions {
    static let shared = OverlayDragExclusions()
    private var frames: [String: CGRect] = [:]

    func report(_ frame: CGRect, for key: String) {
        frames[key] = frame
    }

    /// The reported frames in AppKit content coordinates (y up),
    /// ready for the monitor's hit decision.
    func appKitRects(contentHeight: CGFloat) -> [CGRect] {
        frames.values.map { rect in
            CGRect(x: rect.minX, y: contentHeight - rect.maxY, width: rect.width, height: rect.height)
        }
    }
}

/// Measures the view's frame and reports it as a drag exclusion.
private struct DragExclusionReporter: ViewModifier {
    let key: String

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { OverlayDragExclusions.shared.report(proxy.frame(in: .global), for: key) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        OverlayDragExclusions.shared.report(frame, for: key)
                    }
            }
        }
    }
}

extension View {
    /// Marks a header control as click-only territory for the
    /// overlay's drag monitor: presses here never start a drag.
    func dragExclusion(_ key: String) -> some View {
        modifier(DragExclusionReporter(key: key))
    }
}

/// The overlay content: header, transcript and answer panes,
/// action row, ask box. One material card, nothing else drawn.
struct OverlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reading.transcriptFontSize") private var transcriptFontSize = 14.0
    @State private var askText = ""

    var body: some View {
        let session = model.session
        let collapsed = model.overlay.isCollapsed
        VStack(spacing: Space.sm) {
            // The whole header is the drag handle (the controller's
            // event monitor does the moving); it carries no grip
            // glyph, because a surface you can simply grab does not
            // need to advertise a handle.
            HStack(spacing: Space.sm) {
                StatusDot(listening: session.isListening)
                    .fixedSize()
                Text(session.status)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                Text(model.activeMode().definition.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(session.isListening ? "Stop" : "Start") { session.toggle() }
                    .buttonStyle(InkButtonStyle(compact: true))
                    .dragExclusion("startStop")
                Button(collapsed ? "Expand" : "Collapse", systemImage: collapsed ? "chevron.down" : "minus") { model.overlay.toggleCollapse() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietButtonStyle())
                    .help(collapsed ? "Expand the overlay" : "Collapse to the header bar")
                    .dragExclusion("collapse")
                Button("Close", systemImage: "xmark") { model.overlay.hide() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietButtonStyle())
                    .help("Close the overlay (⌘⇧H)")
                    .dragExclusion("close")
            }
            .help("Drag to move the overlay")

            if !collapsed {
                HSplitView {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        paneLabel("Transcript")
                        transcriptList
                    }
                    .frame(minWidth: 160)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        paneLabel("Answer")
                        answerView
                    }
                    .frame(minWidth: 200)
                }

                actionRow

                // One inset field for asking, with its two actions
                // inside the field's trailing edge.
                HStack(spacing: Space.xs) {
                    TextField("Ask anything", text: $askText)
                        .textFieldStyle(.plain)
                        .onSubmit(sendAsk)
                    Button("Screenshot", systemImage: "camera") { session.captureScreenshot() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(QuietButtonStyle())
                        .help("Screenshot the front window and attach it to the next answer (⌘⇧S)")
                    Button("Ask", systemImage: "paperplane") { sendAsk() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(QuietButtonStyle())
                        .help("Ask with the live transcript and your context files")
                }
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background {
                    RoundedRectangle(cornerRadius: Radius.card + 2, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
        }
        .padding(Space.md)
        .frame(minWidth: 400, minHeight: collapsed ? OverlayController.collapsedHeight : 320)
        .background {
            RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            // The bright top edge: light catching the material.
            RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }

    /// A small caps label over a pane: wayfinding, not chrome.
    private func paneLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }

    private func sendAsk() {
        model.session.ask(askText)
        askText = ""
    }

    private var transcriptList: some View {
        AutoScrollTranscript(
            segments: model.session.displaySegments,
            fontSize: transcriptFontSize,
            emptyText: "Nothing heard yet. Start listening, then speak or let the other side speak."
        )
    }

    private var answerView: some View {
        HStack(spacing: 0) {
            AnswerRail(active: model.session.isAnswering || !model.session.answer.isEmpty)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.sm) {
                    if let error = model.session.answerError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if model.session.answer.isEmpty, !model.session.isAnswering, model.session.answerError == nil {
                        Text("Answers appear here. Wait for a question, press an action, or type in the ask box.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    } else {
                        AnswerTextView(text: model.session.answer)
                            .transition(.opacity)
                    }
                    if model.session.isAnswering {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Space.sm)
            }
        }
        .animation(Motion.contentSwap(reduceMotion: reduceMotion), value: model.session.answer.isEmpty)
    }

    private var actionRow: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(AnswerAction.allCases.enumerated()), id: \.offset) { index, action in
                Button(action.title) { model.session.runAction(action, typedQuestion: nil) }
                    .buttonStyle(ChipButtonStyle())
                    .help("\(action.title) (⌘\(index + 1))")
            }
        }
    }
}

/// Global shortcuts through Carbon. No permission needed. Registration
/// failures are kept and shown in Settings, General.
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    weak var model: AppModel?
    private(set) var failures: [String] = []
    private var refs: [EventHotKeyRef?] = []

    private struct Combo {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
        let run: (AppModel) -> Void
    }

    private var combos: [Combo] {
        let cmdShift = UInt32(cmdKey | shiftKey)
        let cmd = UInt32(cmdKey)
        var list: [Combo] = [
            Combo(id: 1, keyCode: UInt32(kVK_ANSI_L), modifiers: cmdShift, label: "⌘⇧L Listening") { $0.session.toggle() },
            Combo(id: 2, keyCode: UInt32(kVK_ANSI_H), modifiers: cmdShift, label: "⌘⇧H Overlay") { $0.overlay.toggle() },
            Combo(id: 3, keyCode: UInt32(kVK_ANSI_S), modifiers: cmdShift, label: "⌘⇧S Screenshot") { $0.session.captureScreenshot() },
        ]
        let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7]
        for (index, action) in AnswerAction.allCases.enumerated() {
            list.append(Combo(id: UInt32(10 + index), keyCode: UInt32(keyCodes[index]), modifiers: cmd, label: "⌘\(index + 1) \(action.title)") { model in
                model.session.runAction(action, typedQuestion: nil)
            })
        }
        return list
    }

    func registerAll() {
        guard refs.isEmpty else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            let id = hotkeyID.id
            Task { @MainActor in HotkeyCenter.shared.fire(id: id) }
            return noErr
        }, 1, &spec, nil, nil)

        for combo in combos {
            let hotkeyID = EventHotKeyID(signature: OSType(0x4954_4149), id: combo.id) // "ITAI"
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
            if status != noErr {
                failures.append("\(combo.label): registration failed (\(status)). Another app may own it.")
            }
            refs.append(ref)
        }
    }

    @MainActor
    private func fire(id: UInt32) {
        guard let model else { return }
        combos.first { $0.id == id }?.run(model)
    }

    var shortcutList: [(label: String, combo: String)] {
        var rows: [(label: String, combo: String)] = [
            (label: "Start or stop listening", combo: "⌘⇧L"),
            (label: "Show or hide the overlay", combo: "⌘⇧H"),
            (label: "Screenshot the front window", combo: "⌘⇧S"),
        ]
        for (index, action) in AnswerAction.allCases.enumerated() {
            rows.append((label: action.title, combo: "⌘\(index + 1)"))
        }
        return rows
    }
}
