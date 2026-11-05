import AppKit
import Carbon
import SwiftUI
import InterviewAIKit

/// The floating panel over the call window. Non-activating, so the call
/// app keeps focus while the user reads and clicks actions here.
/// Borderless on purpose: the system title bar gave the panel a second,
/// mismatched chrome (and traffic lights that did nothing useful on a
/// panel), so the view draws the whole surface itself, one rounded
/// rect with a hairline, and carries its own collapse and close
/// buttons in the header. Dragging the header moves the panel.
@Observable
final class OverlayController {
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var expandedHeight: CGFloat = 520
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
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            let host = MovableHostingView(rootView: AnyView(OverlayView().environment(model)))
            panel.contentView = host
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.maxX - 580, y: frame.maxY - 540))
            }
            self.panel = panel
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

    /// Grip dragging: the header grip records where the panel stood
    /// when the drag began, then follows the pointer. Screen space is
    /// y-up, SwiftUI drag space is y-down, so the y flips.
    @ObservationIgnored private var dragOrigin: NSPoint?

    var dragStarted: Bool { dragOrigin != nil }

    func beginDrag() {
        dragOrigin = panel?.frame.origin
    }

    func drag(translation: CGSize) {
        guard let panel, let dragOrigin else { return }
        panel.setFrameOrigin(NSPoint(x: dragOrigin.x + translation.width, y: dragOrigin.y - translation.height))
    }

    func endDrag() {
        dragOrigin = nil
    }

    /// Collapse to the header bar, or back to the remembered height.
    /// The top edge stays put; the panel grows and shrinks downward.
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
        panel.setFrame(frame, display: true)
    }
}

/// The hosting view for the overlay panel. A plain NSHostingView
/// reports that a mouse-down cannot move its window, which silently
/// defeats the panel's movable-by-background setting: the overlay
/// looked draggable and was not. This one says yes, so dragging any
/// free surface of the panel moves it.
final class MovableHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// The overlay content: transcript left, answer right, action row, ask box.
struct OverlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reading.transcriptFontSize") private var transcriptFontSize = 14.0
    @State private var askText = ""

    var body: some View {
        let session = model.session
        let collapsed = model.overlay.isCollapsed
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .help("Drag to move the overlay")
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if model.overlay.dragStarted == false { model.overlay.beginDrag() }
                                model.overlay.drag(translation: value.translation)
                            }
                            .onEnded { _ in model.overlay.endDrag() }
                    )
                StatusDot(listening: session.isListening)
                Text(session.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(model.activeMode().definition.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(session.isListening ? "Stop" : "Start") { session.toggle() }
                    .buttonStyle(InkButtonStyle(compact: true))
                Button(collapsed ? "Expand" : "Collapse", systemImage: collapsed ? "chevron.down" : "minus") { model.overlay.toggleCollapse() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietButtonStyle())
                    .help(collapsed ? "Expand the overlay" : "Collapse to the header bar")
                Button("Close", systemImage: "xmark") { model.overlay.hide() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietButtonStyle())
                    .help("Close the overlay (⌘⇧H)")
            }

            if !collapsed {
                HSplitView {
                    transcriptList
                        .frame(minWidth: 160)
                    answerView
                        .frame(minWidth: 200)
                }

                actionRow

                HStack(spacing: Space.sm) {
                    TextField("Ask anything", text: $askText)
                        .textFieldStyle(.roundedBorder)
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
            }
        }
        .padding(Space.md)
        .frame(minWidth: 400, minHeight: collapsed ? OverlayController.collapsedHeight : 320)
        .background {
            RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                .strokeBorder(Surface.hairline, lineWidth: 1)
        }
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
