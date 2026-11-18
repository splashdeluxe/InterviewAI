import AppKit
import InterviewAIKit
import SwiftData
import SwiftUI

/// The command palette (⌘K): one keyboard box that jumps to any
/// page or meeting and runs the actions that otherwise sit in
/// menus and detail toolbars. The reel's lesson, in native form:
/// the app is driven from the keyboard, and the box is frosted
/// glass like the overlay, because it floats over the work the
/// same way. Ranking lives in the Kit (PaletteFilter); this file
/// builds the items from live state and runs what was picked.
struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var fieldFocused: Bool

    /// One row on screen: the Kit item, its symbol, and what
    /// running it does.
    private struct Entry {
        let item: PaletteItem
        let symbol: String
        let run: () -> Void
    }

    var body: some View {
        let entries = allEntries()
        let visible = visibleEntries(entries)
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Type a command or search meetings", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                if !query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.md)
            Rectangle().fill(Surface.hairline).frame(height: 1)
            resultsList(visible)
            Rectangle().fill(Surface.hairline).frame(height: 1)
            HStack(spacing: Space.md) {
                Text("↑↓ Navigate")
                Text("↵ Run")
                Text("esc Close")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
        }
        .frame(width: 580)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
            .strokeBorder(Surface.hairline, lineWidth: 1))
        .onAppear { fieldFocused = true }
        .onChange(of: query) { selectedIndex = 0 }
        .onMoveCommand { direction in
            if direction == .up { moveSelection(by: -1, count: visible.count) }
            if direction == .down { moveSelection(by: 1, count: visible.count) }
        }
        .onSubmit {
            if visible.indices.contains(selectedIndex) { run(visible[selectedIndex]) }
        }
        .onExitCommand { CommandPaletteWindow.close() }
    }

    /// The result rows: grouped with headers while the box is
    /// empty, one ranked list once a query narrows it down.
    @ViewBuilder
    private func resultsList(_ visible: [Entry]) -> some View {
        if visible.isEmpty {
            Text(query.isEmpty ? "Nothing to run yet." : "No results for \u{201C}\(query)\u{201D}")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
        } else if query.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groups = Dictionary(grouping: visible, by: \.item.group)
                    ForEach(groupOrder, id: \.self) { group in
                        if let rows = groups[group], !rows.isEmpty {
                            Text(group)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Space.md)
                                .padding(.top, Space.sm)
                                .padding(.bottom, Space.xs)
                            ForEach(rows, id: \.item.id) { entry in
                                rowView(entry, index: visible.firstIndex { $0.item.id == entry.item.id } ?? 0)
                            }
                        }
                    }
                }
                .padding(.vertical, Space.sm)
            }
            .frame(maxHeight: 368)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.item.id) { index, entry in
                        rowView(entry, index: index)
                    }
                }
                .padding(.vertical, Space.sm)
            }
            .frame(maxHeight: 368)
        }
    }

    private func rowView(_ entry: Entry, index: Int) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: entry.symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(entry.item.title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: Space.sm)
            if !entry.item.subtitle.isEmpty {
                Text(entry.item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(index == selectedIndex ? Surface.inset : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .contentShape(Rectangle())
        .onHover { if $0 { selectedIndex = index } }
        .onTapGesture { run(entry) }
    }

    private func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    /// The window closes first, so the action's sheet or window
    /// lands on the main window, not under the palette.
    private func run(_ entry: Entry) {
        let action = entry.run
        CommandPaletteWindow.close()
        DispatchQueue.main.async { action() }
    }

    private var groupOrder: [String] { ["Actions", "Go to", "Meeting", "Modes", "Meetings"] }

    private func visibleEntries(_ entries: [Entry]) -> [Entry] {
        guard !query.isEmpty else { return entries }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.item.id, $0) })
        return PaletteFilter.ranked(entries.map(\.item), query: query).compactMap { byID[$0.id] }
    }

    // MARK: Items

    private func allEntries() -> [Entry] {
        var entries: [Entry] = []
        let session = model.session

        // Actions first: the palette opens on what you can do now.
        entries.append(Entry(
            item: PaletteItem(id: "action.session",
                              title: session.isListening ? "Stop Listening" : "Start Listening",
                              subtitle: "Session", group: "Actions",
                              keywords: "record transcribe call meeting setup end pause delete"),
            symbol: session.isListening ? "stop.circle" : "waveform",
            run: {
                if session.isListening {
                    SessionControlsWindow.show(session: session, quitMode: false)
                } else {
                    model.sidebar = .live
                    session.setupRequested = true
                }
            }))
        entries.append(Entry(
            item: PaletteItem(id: "action.overlay",
                              title: model.overlay.isShown ? "Hide Overlay" : "Show Overlay",
                              subtitle: "Session", group: "Actions",
                              keywords: "floating panel answers"),
            symbol: "macwindow.on.rectangle",
            run: { model.overlay.toggle() }))
        entries.append(Entry(
            item: PaletteItem(id: "action.settings", title: "Settings",
                              subtitle: "App", group: "Actions", keywords: "preferences providers speech general"),
            symbol: "gearshape",
            run: { model.openSettingsAction?() }))
        entries.append(Entry(
            item: PaletteItem(id: "action.shortcuts", title: "Keyboard Shortcuts",
                              subtitle: "App", group: "Actions", keywords: "keys hotkeys list"),
            symbol: "keyboard",
            run: { ShortcutsWindow.show() }))
        entries.append(Entry(
            item: PaletteItem(id: "action.report", title: "Report an Issue",
                              subtitle: "App", group: "Actions", keywords: "bug feedback problem"),
            symbol: "ant",
            run: { ReportIssueWindow.show() }))
        entries.append(Entry(
            item: PaletteItem(id: "action.about", title: "About InterviewAI",
                              subtitle: "App", group: "Actions", keywords: "version support whats new"),
            symbol: "info.circle",
            run: { AboutWindow.show() }))

        // Pages.
        let pageHints: [SidebarItem: (subtitle: String, keywords: String)] = [
            .live: ("Session", "record listen call now"),
            .meetings: ("Past sessions", "history calls recordings"),
            .modes: ("Answer modes", "persona style prompts"),
            .context: ("Documents", "files cv resume job description"),
            .intelligence: ("Profile docs", "talking points company intel cover letter"),
            .ask: ("Ask across meetings", "question search answer history"),
        ]
        for page in SidebarItem.allCases {
            let hint = pageHints[page] ?? ("", "")
            entries.append(Entry(
                item: PaletteItem(id: "page.\(page.rawValue)", title: page.title,
                                  subtitle: hint.subtitle, group: "Go to", keywords: hint.keywords),
                symbol: page.symbol,
                run: { model.sidebar = page }))
        }

        // The selected meeting's own actions, when there is one.
        if let selected = meetings.first(where: { $0.id == model.selectedMeeting }) {
            entries.append(contentsOf: meetingEntries(for: selected))
        }

        // Modes.
        for definition in BuiltInModes.all {
            entries.append(Entry(
                item: PaletteItem(id: "mode.\(definition.id)", title: "Use \(definition.name)",
                                  subtitle: "Mode", group: "Modes", keywords: "switch mode \(definition.name)"),
                symbol: "person.wave.2",
                run: { model.activeModeID = definition.id }))
        }
        for custom in model.customModes() {
            entries.append(Entry(
                item: PaletteItem(id: "mode.\(custom.idString)", title: "Use \(custom.name)",
                                  subtitle: "Mode", group: "Modes", keywords: "switch mode \(custom.name)"),
                symbol: "person.wave.2",
                run: { model.activeModeID = custom.idString }))
        }

        // Meetings, newest first (the query's order already is).
        // The palette carries the newest 25; older ones live one
        // click deeper, on the Meetings page itself.
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        for meeting in meetings.prefix(25) {
            entries.append(Entry(
                item: PaletteItem(id: "meeting.\(meeting.uuid.uuidString)", title: meeting.title,
                                  subtitle: formatter.string(from: meeting.startedAt),
                                  group: "Meetings", keywords: "open meeting call session"),
                symbol: "clock.arrow.circlepath",
                run: {
                    model.sidebar = .meetings
                    model.selectedMeeting = meeting.id
                }))
        }
        return entries
    }

    /// The detail toolbar of the selected meeting, as palette
    /// rows. The Deep actions navigate to the meeting first, so
    /// their progress and result land where the user can see them.
    private func meetingEntries(for meeting: Meeting) -> [Entry] {
        let group = "Meeting"
        let open: () -> Void = {
            model.sidebar = .meetings
            model.selectedMeeting = meeting.id
        }
        return [
            Entry(item: PaletteItem(id: "meetingAction.clean", title: "Clean Transcript",
                                    subtitle: meeting.title, group: group, keywords: "polish transcript deep"),
                  symbol: "sparkles",
                  run: { open(); TranscriptCleaner.clean(meeting: meeting, onProgress: { _, _ in }, onDone: { _ in }) }),
            Entry(item: PaletteItem(id: "meetingAction.questions", title: "Find Questions",
                                    subtitle: meeting.title, group: group, keywords: "questions answers asked deep"),
                  symbol: "questionmark.circle",
                  run: { open(); QuestionFinder.find(meeting: meeting, onProgress: { _, _ in }, onDone: { _ in }) }),
            Entry(item: PaletteItem(id: "meetingAction.summary", title: "Regenerate Summary",
                                    subtitle: meeting.title, group: group, keywords: "summary notes deep"),
                  symbol: "arrow.clockwise",
                  run: { open(); MeetingImporter.summarize(meeting: meeting) }),
            Entry(item: PaletteItem(id: "meetingAction.copySummary", title: "Copy Summary",
                                    subtitle: meeting.title, group: group, keywords: "clipboard summary"),
                  symbol: "doc.on.doc",
                  run: {
                      NSPasteboard.general.clearContents()
                      NSPasteboard.general.setString(meeting.summary, forType: .string)
                  }),
            Entry(item: PaletteItem(id: "meetingAction.copyTranscript", title: "Copy Transcript",
                                    subtitle: meeting.title, group: group, keywords: "clipboard transcript"),
                  symbol: "doc.on.doc",
                  run: {
                      NSPasteboard.general.clearContents()
                      NSPasteboard.general.setString(TranscriptSegment.plainText(meeting.segments), forType: .string)
                  }),
        ]
    }
}

/// A borderless panel that can still take the keyboard: the
/// palette is typed in, so it must become key, unlike the overlay.
private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
enum CommandPaletteWindow {
    private static var controller: NSWindowController?
    private static let closeWatcher = CloseWatcher()

    private final class CloseWatcher: NSObject, NSWindowDelegate {
        func windowDidResignKey(_ notification: Notification) {
            CommandPaletteWindow.close()
        }
    }

    static func show(model: AppModel) {
        let view = CommandPaletteView()
            .environment(model)
            .modelContainer(model.container)
            .themed()
        if let controller, let window = controller.window {
            window.contentView = hostingView(for: view)
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            DispatchQueue.main.async { position(window) }
            return
        }
        let window = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = closeWatcher
        window.contentView = hostingView(for: view)
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DispatchQueue.main.async { position(window) }
    }

    /// The hosting view sizes the window to the SwiftUI content,
    /// so the panel is exactly as tall as the results it shows.
    private static func hostingView<V: View>(for view: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        return hosting
    }

    static func close() {
        controller?.close()
    }

    /// Centered on the main window, a step down from its top; on
    /// the screen when there is no main window to hang it on.
    private static func position(_ window: NSWindow) {
        let size = window.frame.size
        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" && $0.isVisible })
            ?? NSApp.mainWindow {
            let frame = main.frame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 120
            ))
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 120
            ))
        }
    }
}
