import AppKit
import SwiftUI

extension Notification.Name {
    /// Help, Replay setup asks the main window to show the wizard again.
    static let replayOnboarding = Notification.Name("InterviewAI.replayOnboarding")
}

/// The rail's height, reported by the sidebar so the root overlay
/// can level the hover tag with the rail's foot row.
private struct SidebarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @AppStorage("onboarding.v2.completed") private var onboardingV2Completed = false
    @State private var showOnboarding = false
    @State private var hoveredRailID: String?
    @State private var sidebarHeight: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            // Arcs: switching pages is the detail's one journey, so
            // the incoming page travels the arc (in lifted from the
            // trailing side, out dropped the other way) instead of
            // cutting or sliding straight. The `.id` makes the switch
            // a real transition, and the sheet timing (slow in, slow
            // out) rides on the sidebar value, so a switch mid-flight
            // retargets instead of queueing.
            page
                .id(model.sidebar ?? .live)
                .arcIn()
                .animation(Motion.sheet, value: model.sidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Surface.canvas)
        }
        .overlay(alignment: .topLeading) { railHoverLabel }
        .onPreferenceChange(SidebarHeightKey.self) { sidebarHeight = $0 }
        .onAppear {
            model.openSettingsAction = { openSettings() }
            // The v2 wizard is for fresh installs only: an install
            // that finished the 1.10.0 card never sees it. The dev
            // tools (snapshots, seed data) never see it either; that
            // skip is explicit here, not seeding luck.
            let env = ProcessInfo.processInfo.environment
            if !onboardingV2Completed, !onboardingCompleted,
               env["APP_SNAPSHOT"] == nil, env["APP_SEED"] == nil {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .replayOnboarding)) { _ in
            showOnboarding = true
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                onboardingCompleted = true
                onboardingV2Completed = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    /// The sidebar is an icon rail, rebuilt after the Muse rail
    /// Nils recorded: quiet icons in a fixed 64 pt column, the
    /// current page filled, and on hover a name tag slides out of
    /// the rail's edge (see `railHoverLabel`). The tag is drawn by
    /// the root overlay, not by the rail itself, so it crosses the
    /// split view's column edge without being clipped.
    private var sidebar: some View {
        VStack(spacing: 0) {
            railHeader
            // Staggering: the six icons arrive one after another on
            // first appearance, by index, instead of all in unison.
            // It is a first-appearance moment only; selecting a page
            // afterwards animates nothing here.
            VStack(spacing: Space.xs) {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, page in
                    railButton(page, index: index)
                }
            }
            .padding(.top, Space.sm)
            Spacer(minLength: 0)
            railFoot
        }
        .navigationSplitViewColumnWidth(min: 64, ideal: 64, max: 64)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SidebarHeightKey.self, value: proxy.size.height)
            }
        }
    }

    /// The product mark at the top of the rail: the same ink tile
    /// the wide sidebar carried, now on its own.
    private var railHeader: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Surface.ink)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Surface.onInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.md)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Surface.hairline).frame(height: 1)
            }
    }

    /// One page in the rail: an icon in a 40 pt target, filled when
    /// it is the current page, lit on hover. Selecting sets the
    /// same sidebar value the old list bound to, so page switching,
    /// the palette and the shortcuts all keep their one path.
    private func railButton(_ page: SidebarItem, index: Int) -> some View {
        let selected = (model.sidebar ?? .live) == page
        let hovered = hoveredRailID == page.id
        return Button {
            model.sidebar = page
        } label: {
            Image(systemName: page.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected || hovered ? Surface.ink : Color.secondary)
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(selected ? Surface.inset : hovered ? Surface.control : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.title)
        .staggered(index: index)
        .onHover { inside in
            if inside {
                hoveredRailID = page.id
            } else if hoveredRailID == page.id {
                hoveredRailID = nil
            }
        }
        .animation(Motion.press, value: hovered)
    }

    /// The foot of the rail: the corner menu and the session dot
    /// side by side on a panel step, split from the icons by one
    /// hairline. Their words live in the hover tag, like the pages'.
    private var railFoot: some View {
        HStack(spacing: Space.sm) {
            cornerMenuButton
                .onHover { inside in
                    if inside {
                        hoveredRailID = "menu"
                    } else if hoveredRailID == "menu" {
                        hoveredRailID = nil
                    }
                }
            StatusDot(listening: model.session.isListening)
                .frame(width: 16, height: 16)
                .onHover { inside in
                    if inside {
                        hoveredRailID = "status"
                    } else if hoveredRailID == "status" {
                        hoveredRailID = nil
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
        .background(Surface.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Surface.hairline).frame(height: 1)
        }
    }

    /// The hover tag: a small panel card that slides out of the
    /// rail's trailing edge, level with the icon under the pointer.
    /// Hit testing is off, so it never eats a click meant for a page.
    private var railHoverLabel: some View {
        ZStack(alignment: .topLeading) {
            if let id = hoveredRailID, let text = railLabelText(for: id),
               let midY = railLabelMidY(for: id) {
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Surface.ink)
                    .padding(.horizontal, Space.sm)
                    .frame(height: 32)
                    .panelSurface(radius: Radius.control)
                    .offset(x: 64 + Space.sm, y: midY - 16) // grid: ok the tag is placed from the rail's fixed layout, not nudged
                    .transition(.opacity.combined(with: .offset(x: -4))) // grid: ok the tag slides the last 4 pt out of the rail edge
            }
        }
        .animation(Motion.pop, value: hoveredRailID)
        .allowsHitTesting(false)
    }

    /// What the hover tag says for a rail target: a page's name,
    /// the menu's name, or the session state in words, the two
    /// pieces of text the old status strip carried.
    private func railLabelText(for id: String) -> String? {
        if let page = SidebarItem(rawValue: id) { return page.title }
        switch id {
        case "menu":
            return "Menu"
        case "status":
            let state = model.session.isListening ? "Listening" : "Idle"
            let detail = model.session.status
            return detail.isEmpty || detail == state ? state : "\(state) · \(detail)"
        default:
            return nil
        }
    }

    /// Where the hover tag sits, from the rail's fixed layout: the
    /// header block is 52 (tile 28, padding 12 above and below),
    /// the icons start 8 lower, each is 40 tall with 4 between, and
    /// the foot row's centre is 25 above the rail's foot (padding
    /// 12 plus half the 26 pt menu button).
    private func railLabelMidY(for id: String) -> CGFloat? {
        if let page = SidebarItem(rawValue: id),
           let index = SidebarItem.allCases.firstIndex(of: page) {
            return 52 + Space.sm + 20 + CGFloat(index) * 44
        }
        guard id == "menu" || id == "status", sidebarHeight > 0 else { return nil }
        return sidebarHeight - 25 // grid: ok 12 padding plus half the 26 pt menu button
    }

    /// The corner menu: one round button at the foot of the sidebar,
    /// opening a native menu. A native menu renders correctly in both
    /// appearances (the old custom dark popover could come up white on
    /// white) and gives the shortcuts a real submenu.
    private var cornerMenuButton: some View {
        Menu {
            Menu {
                ForEach(ShortcutsView.rows) { row in
                    Text("\(row.keys) — \(row.action)")
                }
            } label: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }
            Button {
                ReportIssueWindow.show()
            } label: {
                Label("Report an Issue", systemImage: "ant")
            }
            Divider()
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Surface.onInk)
                .frame(width: 26, height: 26) // grid: ok glyph hit frame
                .background(Circle().fill(Surface.ink))
        }
        .menuIndicator(.hidden)
        .help("Menu")
    }

    @ViewBuilder
    private var page: some View {
        switch model.sidebar ?? .live {
        case .live: LivePage()
        case .meetings: MeetingsPage()
        case .modes: ModesPage()
        case .context: ContextPage()
        case .intelligence: IntelligencePage()
        case .ask: AskPage()
        }
    }
}

