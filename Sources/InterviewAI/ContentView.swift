import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var cornerMenuShown = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Surface.canvas)
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

    /// The corner menu, shaped after the reference Nils sent: one round
    /// button at the foot of the sidebar, opening a small dark card with
    /// Keyboard Shortcuts, Report an Issue, and Settings.
    private var cornerMenuButton: some View {
        Button {
            cornerMenuShown.toggle()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Surface.onInk)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Surface.ink))
        }
        .buttonStyle(.plain)
        .help("Menu")
        .popover(isPresented: $cornerMenuShown, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            cornerMenu
        }
    }

    /// Close the card first, then run the row's action a beat later.
    /// Acting in the same tick as the dismissal can swallow the action:
    /// the Settings scene and the browser open both get dropped when
    /// they fire while the popover is still tearing down.
    private func cornerAction(_ action: @escaping () -> Void) {
        cornerMenuShown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { action() }
    }

    private var cornerMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            CornerMenuRow(icon: "keyboard", title: "Keyboard Shortcuts", shortcut: "⌘/") {
                cornerAction { ShortcutsWindow.show() }
            }
            CornerMenuRow(icon: "ant", title: "Report an Issue", shortcut: nil) {
                cornerAction { ReportIssueWindow.show() }
            }
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
                .padding(.vertical, Space.xs)
            CornerMenuRow(icon: "gearshape", title: "Settings", shortcut: "⌘,") {
                cornerAction { openSettings() }
            }
        }
        .padding(Space.sm)
        .frame(width: 264)
        .background(Surface.ink)
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

/// One row of the corner menu: icon, title, and the shortcut in muted
/// type at the trailing edge, with a soft highlight under the pointer.
struct CornerMenuRow: View {
    let icon: String
    let title: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut).foregroundStyle(.white.opacity(0.45))
                }
            }
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
