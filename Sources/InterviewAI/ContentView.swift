import AppKit
import SwiftUI

extension Notification.Name {
    /// Help, Replay setup asks the main window to show the wizard again.
    static let replayOnboarding = Notification.Name("InterviewAI.replayOnboarding")
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @AppStorage("onboarding.v2.completed") private var onboardingV2Completed = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Surface.canvas)
        }
        .onAppear {
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

    private var sidebar: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            sidebarHeader
            List(SidebarItem.allCases, selection: $model.sidebar) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .listStyle(.sidebar)
            statusStrip
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }

    /// The product names itself at the top of the shell: a plain ink
    /// mark, the name, and the active mode as the scope under it.
    private var sidebarHeader: some View {
        HStack(spacing: Space.sm) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Surface.ink)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Surface.onInk)
                }
            VStack(alignment: .leading, spacing: 0) {
                Text("InterviewAI")
                    .font(.callout.weight(.semibold))
                Text(model.activeMode().definition.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Surface.hairline).frame(height: 1)
        }
    }

    /// The session state sits at the foot of the sidebar, on a panel
    /// step, split from the list by one hairline.
    private var statusStrip: some View {
        HStack(spacing: Space.sm) {
            cornerMenuButton
            StatusDot(listening: model.session.isListening)
            Text(model.session.isListening ? "Listening" : "Idle")
                .font(.caption.weight(.medium))
            Spacer(minLength: 0)
            Text(model.session.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(Space.md)
        .background(Surface.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Surface.hairline).frame(height: 1)
        }
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

