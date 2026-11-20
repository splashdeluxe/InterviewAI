import AppKit
import InterviewAIKit
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Nils recorded: quiet icons in a fixed 80 pt column, the
    /// current page filled, and on hover a name tag slides out
    /// of the rail's edge (see `railHoverLabel`). The tag is
    /// drawn by the root overlay, not by the rail itself, so
    /// it crosses the split view's column edge without being
    /// clipped. Names only, no shortcuts in the tag: the
    /// tags were removed for one round on the "without the
    /// text" call, then Nils asked for them back as names
    /// alone. No logo tile at the top either: Nils deleted
    /// that, the rail starts with the icons. The rail and
    /// its icons were sized up once, at Nils's word: the
    /// first cut read too small.
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Staggering: the six icons arrive one after another on
            // first appearance, by index, instead of all in unison.
            // It is a first-appearance moment only; selecting a page
            // afterwards animates nothing here.
            VStack(spacing: Space.sm) {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, page in
                    railButton(page, index: index)
                }
            }
            .padding(.top, Space.sm)
            Spacer(minLength: 0)
            railFoot
        }
        .navigationSplitViewColumnWidth(min: 80, ideal: 80, max: 80)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SidebarHeightKey.self, value: proxy.size.height)
            }
        }
    }

    /// One page in the rail: an icon in a 52 pt target, filled when
    /// it is the current page, lit on hover. Selecting sets the
    /// same sidebar value the old list bound to, so page switching,
    /// the palette and the shortcuts all keep their one path.
    private func railButton(_ page: SidebarItem, index: Int) -> some View {
        RailPageButton(
            page: page,
            selected: (model.sidebar ?? .live) == page,
            hovered: hoveredRailID == page.id,
            reduceMotion: reduceMotion,
            onSelect: { model.sidebar = page },
            onHover: { inside in
                if inside {
                    hoveredRailID = page.id
                } else if hoveredRailID == page.id {
                    hoveredRailID = nil
                }
            }
        )
        .staggered(index: index)
    }

    /// The foot of the rail: the corner menu alone on a
    /// panel step, split from the icons by one hairline.
    /// Its word lives in the hover tag, like the pages'.
    /// The menu sits centred in a row, as the original
    /// foot had it.
    private var railFoot: some View {
        HStack {
            Spacer()
            cornerMenuButton
            Spacer()
        }
        .padding(.vertical, Space.md)
            .background(Surface.panel)
            .overlay(alignment: .top) {
                Rectangle().fill(Surface.hairline).frame(height: 1)
            }
    }

    /// The corner menu, restored at Nils's word after a
    /// round as a Muse-style settings gear beside a status
    /// dot: he called that foot wrong, wanted the menu from
    /// before back, and the dot gone. The button is a plain
    /// button wearing the ink circle, and it pops a native
    /// menu (see CornerMenu below): a SwiftUI Menu draws
    /// its own bezel as a wide pill whatever label it is
    /// given, through three attempted fixes, while a plain
    /// button renders its label as drawn, like the gear
    /// did. On hover the drawn lines stagger, the button
    /// pops, and the Menu tag slides out. The session
    /// state the dot carried still shows on the Live page
    /// and in the overlay.
    private var cornerMenuButton: some View {
        let hovered = hoveredRailID == "menu"
        return Button {
            CornerMenu.popUp(openSettings: { openSettings() })
        } label: {
            MenuGlyph(hovered: hovered, reduceMotion: reduceMotion, tint: Surface.onInk)
                .scaleEffect(hovered && !reduceMotion ? CGFloat(MotionSpec.exaggerationScale) : 1)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Surface.ink))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
        .onHover { inside in
            if inside {
                hoveredRailID = "menu"
            } else if hoveredRailID == "menu" {
                hoveredRailID = nil
            }
        }
        .animation(RailTiming.glide, value: hovered)
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
                    .offset(x: 80 + Space.sm, y: midY - 16) // grid: ok the tag is placed from the rail's fixed layout, not nudged
                    .transition(.opacity.combined(with: .offset(x: -8)).combined(with: .scale(scale: 0.92, anchor: .leading))) // grid: ok the tag springs out of the rail edge, growing from its left edge
            }
        }
        .animation(RailTiming.glide, value: hoveredRailID)
        .allowsHitTesting(false)
    }

    /// What the hover tag says for a rail target: a page's
    /// name, or Menu for the foot's button. Names only.
    private func railLabelText(for id: String) -> String? {
        if let page = SidebarItem(rawValue: id) { return page.title }
        return id == "menu" ? "Menu" : nil
    }

    /// Where the hover tag sits, from the rail's fixed layout:
    /// the icons start 8 below the rail's top (there is no
    /// header block any more), each is 52 tall with 8 between,
    /// and the foot row's centre is 34 above the rail's foot
    /// (padding 12 plus half the 44 pt menu button).
    private func railLabelMidY(for id: String) -> CGFloat? {
        if let page = SidebarItem(rawValue: id),
           let index = SidebarItem.allCases.firstIndex(of: page) {
            return Space.sm + 26 + CGFloat(index) * 60
        }
        guard id == "menu", sidebarHeight > 0 else { return nil }
        return sidebarHeight - 34 // grid: ok 12 padding plus half the 44 pt menu button
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

/// One keyframe of a rail glyph's hover move: how far it lifts,
/// slides and tips, and how it squashes, all from rest.
private struct RailMove: Equatable {
    var lift: CGFloat = 0
    var slide: CGFloat = 0
    var tilt: Double = 0
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1

    static let rest = RailMove()
}

/// The rail's hover timing, slower and softer than the app's
/// rubber band: the second pass moved too fast on hover, so
/// the glyph moves, the tag and the button pop glide on
/// these. A keyframed move runs about a second and a half
/// end to end; the glide carries the scale pop and the tag.
enum RailTiming {
    static let glide = Animation.spring(response: 0.45, dampingFraction: 0.8)
    static let phase = Animation.spring(response: 0.34, dampingFraction: 0.74)
}

/// One page button in the rail. It owns its hover-play trigger,
/// so a glyph's move fires on hover-in only and never replays
/// on the way out. The glyph is drawn, not a symbol font: the
/// run 1 prototype ported natively in RailGlyphs. Most moves
/// live inside the glyph; the card's tip and the magnifier's
/// search move the whole glyph and are applied here.
private struct RailPageButton: View {
    let page: SidebarItem
    let selected: Bool
    let hovered: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var playCount = 0

    var body: some View {
        Button(action: onSelect) {
            glyph
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(selected ? Surface.inset : hovered ? Surface.control : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.title)
        .onHover { inside in
            if inside && !reduceMotion { playCount += 1 }
            onHover(inside)
        }
        .animation(Motion.press, value: hovered)
    }

    @ViewBuilder
    private var glyph: some View {
        let tint = selected || hovered ? Surface.ink : Color.secondary
        let core = RailGlyph(page: page, hovered: hovered, playCount: playCount,
                             reduceMotion: reduceMotion, tint: tint)
            .frame(width: 28, height: 28)
            .scaleEffect(hovered && !reduceMotion ? CGFloat(MotionSpec.exaggerationScale) : 1)
            .animation(RailTiming.glide, value: hovered)
        if reduceMotion || (page != .intelligence && page != .ask) {
            // The other glyphs carry their moves inside
            // themselves; only the card's tip and the
            // magnifier's search move the whole glyph.
            core
        } else {
            PhaseAnimator(RailMoves.moves(for: page), trigger: playCount) { phase in
                core
                    .offset(x: phase.slide, y: phase.lift) // grid: ok the hover move is keyframed, not a layout nudge
                    .rotationEffect(.degrees(phase.tilt))
                    .scaleEffect(x: phase.squashX, y: phase.squashY)
            } animation: { _ in
                RailTiming.phase
            }
        }
    }
}

/// The whole-glyph hover moves: only the profile card and
/// the magnifier still move as a whole, tipping and
/// searching as they did in the run 1 prototype. The other
/// glyphs carry their moves inside themselves now.
private enum RailMoves {
    static func moves(for page: SidebarItem) -> [RailMove] {
        switch page {
        case .intelligence:
            // The card tips to one side, then the other.
            return [.rest,
                    RailMove(lift: -2, tilt: 12),
                    RailMove(tilt: -7),
                    .rest]
        case .ask:
            // Searching: the glass loops a small circle.
            return [.rest,
                    RailMove(lift: -2, slide: 3),
                    RailMove(lift: 1, slide: -3),
                    RailMove(lift: 2, slide: 2),
                    .rest]
        default:
            return [.rest]
        }
    }
}

/// The corner menu's contents, built as a native menu and
/// popped at the pointer by the foot's button. A native
/// menu renders correctly in both appearances and gives
/// the shortcuts a real submenu; building it by hand is
/// what lets the button itself stay a plain button with
/// a drawn label.
private enum CornerMenu {
    static func popUp(openSettings: @escaping () -> Void) {
        let coordinator = Coordinator.shared
        coordinator.onSettings = openSettings

        let menu = NSMenu()

        let shortcutsItem = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        let shortcutsMenu = NSMenu()
        for row in ShortcutsView.rows {
            shortcutsMenu.addItem(NSMenuItem(title: "\(row.keys) — \(row.action)", action: nil, keyEquivalent: ""))
        }
        shortcutsItem.submenu = shortcutsMenu
        menu.addItem(shortcutsItem)

        let reportItem = NSMenuItem(title: "Report an Issue", action: #selector(Coordinator.report), keyEquivalent: "")
        reportItem.target = coordinator
        menu.addItem(reportItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(Coordinator.settings), keyEquivalent: ",")
        settingsItem.target = coordinator
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// The menu items' target: a small NSObject the
    /// selectors can land on, held for the app's life.
    private final class Coordinator: NSObject {
        static let shared = Coordinator()
        var onSettings: (() -> Void)?

        @objc func settings() { onSettings?() }
        @objc func report() { ReportIssueWindow.show() }
    }
}

