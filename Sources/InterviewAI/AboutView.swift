import AppKit
import SwiftUI

/// The About window: icon, version, what the app is, who made the
/// models and tools inside it, and the update check. Opened from the
/// app menu and from the menu bar icon.
struct AboutView: View {
    @State private var checker = UpdateChecker.shared

    var body: some View {
        VStack(spacing: Space.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: Space.xs) {
                Text("InterviewAI")
                    .font(.title2.weight(.semibold))
                Text("Version \(UpdateChecker.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("by Nils Effmert")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("A free interview copilot for this Mac. It hears both sides of the call, transcribes on the device, and drafts answers with a local model or your own key. No account, licence, trial, quota, or store.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: Space.sm) {
                credit("Parakeet Ultra", detail: "Speech model by Moondream (CC-BY-4.0), a retrain of NVIDIA's Parakeet v3, run on the Neural Engine through FluidAudio (Apache-2.0).")
                credit("Whisper", detail: "WhisperKit by Argmax (MIT). Apple Speech is the third engine.")
                credit("Speakers", detail: "Speaker identification by FluidAudio's diarizer, pyannote segmentation with speaker embeddings, on this Mac.")
                credit("Original code", detail: "Written from scratch by Nils Effmert. No third-party app code, text, prompts, icons, or branding inside.")
            }
            Divider()
            HStack(spacing: Space.sm) {
                Text("Free and open source on GitHub.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openGitHub("https://github.com/splashdeluxe/InterviewAI")
                } label: {
                    Label("Star", systemImage: "star")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Open the repo. A star helps other people find it.")
                Button {
                    openGitHub("https://github.com/splashdeluxe")
                } label: {
                    Label("Follow", systemImage: "person.badge.plus")
                }
                .buttonStyle(QuietButtonStyle())
                .help("Follow @splashdeluxe on GitHub")
            }
            Divider()
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
                Button("Check for Updates") {
                    Task { await checker.check() }
                }
                .disabled(checker.state == .checking)
            }
        }
        .padding(Space.xl)
        .frame(width: 440)
    }

    private func openGitHub(_ address: String) {
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }

    private func credit(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One About window, reused. A plain AppKit window so the app menu,
/// the menu bar icon, and Settings can all open the same one.
@MainActor
enum AboutWindow {
    private static var controller: NSWindowController?

    static func show() {
        if let controller {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "About InterviewAI"
        window.contentView = NSHostingView(rootView: AboutView())
        window.isReleasedWhenClosed = false
        window.center()
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate()
        sizeWindowToContent(window)
    }
}
