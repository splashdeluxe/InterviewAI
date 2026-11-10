import AppKit
import SwiftUI

/// The app info window, in the Vorssaint shape Nils picked on
/// 2026-11-09: a sidebar with About, What's New and Support, the same
/// three sections every one of his apps carries. Opened from the app
/// menu and from the menu bar icon.
enum AppInfoSection: String, CaseIterable, Identifiable {
    case about
    case whatsNew
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .about: "About"
        case .whatsNew: "What's New"
        case .support: "Support"
        }
    }

    var icon: String {
        switch self {
        case .about: "info.circle"
        case .whatsNew: "sparkles"
        case .support: "heart"
        }
    }
}

/// One release's notes, written in the Vorssaint shape: a summary,
/// then Added and Fixed lists, one plain line per change. New
/// releases add an entry at the top; nothing here is fetched.
struct ReleaseNotes: Identifiable {
    let version: String
    let date: String
    let summary: String
    var added: [String] = []
    var fixed: [String] = []

    var id: String { version }

    static let all: [ReleaseNotes] = [
        ReleaseNotes(
            version: "1.11.0", date: "2026-11-10",
            summary: "Dual-Brain: a bigger model for the thinking done outside the call, while live answers stay on the fast one.",
            added: [
                "Settings, Providers gains Dual-Brain. Turn it on and name a Deep model (llama3.1:8b by default): the Ask page, meeting summaries, follow-up drafts and Profile generation use it, one job at a time, and it leaves memory again five minutes after a job finishes.",
                "If the Deep model is missing or a request fails, the job falls back to the live model and the result says so. Answers in a live call never switch models."
            ]
        ),
        ReleaseNotes(
            version: "1.10.0", date: "2026-11-10",
            summary: "The first open now walks through the three permissions the app needs, each with its own enable button, instead of leaving them to be found in Settings.",
            added: [
                "A setup card on first open: meeting detection, microphone and meeting audio, each explained in one line and granted in place. Continue unlocks once microphone and meeting audio are in; meeting detection stays optional.",
                "The icon's fourth bar now carries the raspberry accent; the other four stay white."
            ]
        ),
        ReleaseNotes(
            version: "1.9.1", date: "2026-11-09",
            summary: "About, What's New and Support now also live in Settings, as three tabs of their own next to Help.",
            added: [
                "Settings gains About, What's New and Support tabs carrying the same pages as the standalone window. The app menu route stays; both open the same content."
            ],
            fixed: [
                "The three pages scroll in Settings, so the first lines of About and What's New are no longer clipped on shorter windows."
            ]
        ),
        ReleaseNotes(
            version: "1.9.0", date: "2026-11-09",
            summary: "About, What's New and Support now sit in one window, in the same three sections every one of Nils's apps carries.",
            added: [
                "The app menu opens About, What's New and Support directly. About gains a View on GitHub button, a copyright line and the update settings.",
                "What's New lists each release with a summary and its Added and Fixed lines, and can open on its own after an update.",
                "Support carries the Ko-fi link, the GitHub star card and the bug reporter in one place.",
                "The automatic update check can be turned off in About. The manual check stays."
            ]
        ),
        ReleaseNotes(
            version: "1.8.0", date: "2026-11-08",
            summary: "Meeting history now lets you pick which calendar event a saved meeting belongs to, so a meeting that was saved under the wrong name can be put right after the fact.",
            added: [
                "A Link to Calendar Event button on every saved meeting. The picker lists that day's events, and the pick stamps the title, the invited people, the calendar, the place and the times onto the meeting.",
                "Unlinking a meeting restores the title it was saved with."
            ]
        ),
        ReleaseNotes(
            version: "1.7.0", date: "2026-11-08",
            summary: "Answers now follow the language of the person you are talking to, unless you pin a language yourself.",
            added: [
                "An Answer Language setting under Settings, General, Live Session. The standard setting matches the other side, worked out from the last lines they said.",
                "Pinned languages: English, German, Russian, Indonesian, Spanish and French."
            ]
        ),
        ReleaseNotes(
            version: "1.6.0", date: "2026-11-05",
            summary: "Meetings got easier to read, copy and file, and the summary got a proper structure.",
            added: [
                "The overlay can be dragged to where you want it.",
                "Transcript export to a file. The transcript is now one block of text, so a selection can run across lines and speakers.",
                "Saved meetings carry their calendar name, the invited people and the event details when a matching event exists.",
                "Answer and transcript text size runs from 14 to 24 pt. 14 pt is the standard."
            ],
            fixed: [
                "Summaries were cut off at 400 tokens and had no structure. They now get room to finish and come back with Overview, Key points, Decisions, Action items and Open questions, with empty sections left out."
            ]
        )
    ]
}

struct AboutView: View {
    @State private var section: AppInfoSection

    init(initialSection: AppInfoSection = .about) {
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                Group {
                    switch section {
                    case .about: AboutPane()
                    case .whatsNew: WhatsNewPane()
                    case .support: SupportPane()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.xl)
            }
        }
        .frame(width: 760, height: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(AppInfoSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: item.icon)
                            .frame(width: 20)
                        Text(item.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.sm)
                    .padding(.horizontal, Space.md)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(section == item ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(section == item ? Color.white : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(Space.md)
        .frame(width: 192)
    }
}

// MARK: - About

struct AboutPane: View {
    @State private var checker = UpdateChecker.shared
    @AppStorage("update.automaticCheck") private var automaticCheck = true
    @AppStorage("update.showWhatsNewAfterUpdate") private var showWhatsNewAfterUpdate = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.lg) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("InterviewAI")
                        .font(.title2.weight(.semibold))
                    Text("Version \(UpdateChecker.currentVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("by Nils Effmert")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Text("A free interview copilot for this Mac. It hears both sides of the call, transcribes on the device, and drafts answers with a local model or your own key. No account, licence, trial, quota, or store.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.sm) {
                Button {
                    open("https://github.com/splashdeluxe/InterviewAI")
                } label: {
                    Label("View on GitHub", systemImage: "star")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Open the repo. A star helps other people find it.")
                Button {
                    open("https://github.com/splashdeluxe")
                } label: {
                    Label("Follow", systemImage: "person.badge.plus")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Follow @splashdeluxe on GitHub")
                Spacer()
                Text("© 2026 Nils Effmert")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: Space.sm) {
                credit("Parakeet Ultra", detail: "Speech model by Moondream (CC-BY-4.0), a retrain of NVIDIA's Parakeet v3, run on the Neural Engine through FluidAudio (Apache-2.0).")
                credit("Whisper", detail: "WhisperKit by Argmax (MIT). Apple Speech is the third engine.")
                credit("Speakers", detail: "Speaker identification by FluidAudio's diarizer, pyannote segmentation with speaker embeddings, on this Mac.")
                credit("Original code", detail: "Written from scratch by Nils Effmert. No third-party app code, text, prompts, icons, or branding inside.")
            }
            Divider()
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Updates")
                    .font(.callout.weight(.semibold))
                Toggle("Check for updates automatically", isOn: $automaticCheck)
                    .font(.callout)
                    .toggleStyle(.switch)
                Text("One quiet check a day at launch, against the releases on GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show what's new after updating", isOn: $showWhatsNewAfterUpdate)
                    .font(.callout)
                    .toggleStyle(.switch)
                HStack(spacing: Space.sm) {
                    if checker.state == .checking { ProgressView().controlSize(.small) }
                    Text(checker.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if case .available(_, let url) = checker.state {
                        Link("Get it", destination: url)
                    }
                    Button("Check now") {
                        Task { await checker.check() }
                    }
                    .disabled(checker.state == .checking)
                }
                if let last = UpdateChecker.lastCheck {
                    Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func credit(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open(_ address: String) {
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - What's New

struct WhatsNewPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            ForEach(Array(ReleaseNotes.all.enumerated()), id: \.element.id) { index, release in
                VStack(alignment: .leading, spacing: Space.md) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(index == 0 ? "What's new in this version" : "Version \(release.version)")
                            .font(.title3.weight(.semibold))
                        Text("v\(release.version) · \(release.date)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("SUMMARY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(release.summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if !release.added.isEmpty {
                        changeGroup(title: "ADDED", icon: "plus.circle.fill", lines: release.added)
                    }
                    if !release.fixed.isEmpty {
                        changeGroup(title: "FIXED", icon: "checkmark.circle.fill", lines: release.fixed)
                    }
                }
            }
        }
    }

    private func changeGroup(title: String, icon: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: icon)
                        .foregroundStyle(Color.accentColor)
                    Text(line)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Support

struct SupportPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(spacing: Space.md) {
                ZStack {
                    Circle().fill(Surface.ink)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Surface.onInk)
                }
                .frame(width: 72, height: 72)
                Text("Help InterviewAI keep growing")
                    .font(.title3.weight(.semibold))
                Text("InterviewAI stays free and runs on this Mac, with transcription on the device and no ads or usage tracking. If it helps you, a coffee on Ko-fi is the only way to help fund its development.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    open("https://ko-fi.com/nils_effmert")
                } label: {
                    Label("Support on Ko-fi", systemImage: "cup.and.saucer.fill")
                        .padding(.horizontal, Space.sm)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.md) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.title3)
                    Text("Financial support is never expected. A star on GitHub helps more people discover InterviewAI and makes a real difference to its development.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    open("https://github.com/splashdeluxe/InterviewAI")
                } label: {
                    Label("Star InterviewAI on GitHub", systemImage: "star")
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(Space.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                    .strokeBorder(Surface.hairline, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Something broken?")
                    .font(.callout.weight(.semibold))
                Text("Report it and it is filed as an issue on GitHub, with the app version and system details attached on their own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    ReportIssueWindow.show()
                } label: {
                    Label("Report an Issue", systemImage: "ant")
                }
                .buttonStyle(QuietButtonStyle())
            }

            Text("Thank you for being here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func open(_ address: String) {
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Shows the What's New section once after an update, when the
/// setting in About is on. Called at launch; the first install only
/// records the version and shows nothing.
@MainActor
enum WhatsNewLaunch {
    private static let seenKey = "app.lastSeenVersion"
    private static let settingKey = "update.showWhatsNewAfterUpdate"

    static func run() {
        let current = UpdateChecker.currentVersion
        let seen = UserDefaults.standard.string(forKey: seenKey)
        UserDefaults.standard.set(current, forKey: seenKey)
        guard let seen, seen != current else { return }
        let show = UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
        if show { AboutWindow.show(.whatsNew) }
    }
}

/// One app info window, reused. A plain AppKit window so the app
/// menu, the menu bar icon, and Settings can all open the same one.
@MainActor
enum AboutWindow {
    private static var controller: NSWindowController?

    static func show(_ section: AppInfoSection = .about) {
        if let controller, let window = controller.window {
            window.contentView = NSHostingView(rootView: AboutView(initialSection: section))
            window.title = section == .about ? "About InterviewAI" : section.title
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "About InterviewAI"
        window.contentView = NSHostingView(rootView: AboutView(initialSection: section))
        window.isReleasedWhenClosed = false
        window.center()
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate()
    }
}
