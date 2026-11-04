import AppKit
import SwiftUI
import InterviewAIKit

/// The Report a Bug window, modelled on the reference layout: say what
/// went wrong, attach a screenshot if it helps, and Submit. The report
/// is filed as an issue on GitHub through a small relay, so the app
/// itself holds no token and nobody pastes anything anywhere. The app
/// version, macOS version, and engine are attached on their own.
struct ReportIssueView: View {
    @State private var text = ""
    @State private var screenshot: Data?
    @State private var capturing = false
    @State private var phase: Phase = .writing

    private enum Phase: Equatable {
        case writing, filing, filed(number: Int, url: URL), failed(String)
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .filing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Report a bug")
                    .font(.title3.weight(.semibold))
                Text("Describe what went wrong and it is filed as an issue on GitHub. The app version and system details are attached on their own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("What went wrong?")
                    .font(.callout.weight(.semibold))
                TextEditor(text: $text)
                    .font(.callout)
                    .frame(height: 170)
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Surface.hairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text("Screenshot")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if screenshot != nil {
                        Button("Remove") { screenshot = nil }
                            .buttonStyle(QuietButtonStyle())
                    }
                    Button(capturing ? "Capturing..." : "Capture screen") { captureScreen() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(capturing)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Surface.hairline, lineWidth: 1)
                    if let screenshot, let image = NSImage(data: screenshot) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(Space.sm)
                    } else {
                        Text("No screenshot attached")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 110)
            }

            statusRow

            HStack {
                Spacer()
                Button("Cancel") { ReportIssueWindow.close() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Submit") { submit() }
                    .buttonStyle(InkButtonStyle())
                    .disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.lg)
        .frame(width: 560)
        .background(Surface.canvas)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch phase {
        case .writing:
            EmptyView()
        case .filing:
            HStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text("Filing the issue...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .filed(let number, let url):
            HStack(spacing: Space.sm) {
                Text("Filed as issue #\(number).")
                    .font(.callout)
                Button("Open") { NSWorkspace.shared.open(url) }
                    .buttonStyle(QuietButtonStyle())
            }
        case .failed(let message):
            HStack(spacing: Space.sm) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open the form on GitHub") { openWebForm() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func captureScreen() {
        capturing = true
        Task {
            // The report window steps aside so the shot shows the app
            // and the call behind it, not the report form itself.
            ReportIssueWindow.setVisible(false)
            try? await Task.sleep(nanoseconds: 300_000_000)
            let data = try? await ScreenCapturer.displayJPEG()
            ReportIssueWindow.setVisible(true)
            capturing = false
            if let data {
                screenshot = data
            } else {
                phase = .failed("Screen capture failed. Screen Recording access lives under Settings, Permissions.")
            }
        }
    }

    private func submit() {
        phase = .filing
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let engine = UserDefaults.standard.string(forKey: "transcription.engine") ?? "parakeetUltra"
        let description = text
        let shot = screenshot
        Task {
            do {
                let (number, url) = try await Self.fileViaRelay(description: description,
                                                                version: UpdateChecker.currentVersion,
                                                                macOS: macOS, engine: engine, screenshot: shot)
                phase = .filed(number: number, url: url)
            } catch {
                phase = .failed("Filing failed: \(error.localizedDescription) Your text is still in the box above.")
            }
        }
    }

    private func openWebForm() {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let engine = UserDefaults.standard.string(forKey: "transcription.engine") ?? "parakeetUltra"
        if let url = IssueReport.webURL(description: text, version: UpdateChecker.currentVersion, macOS: macOS, engine: engine) {
            NSWorkspace.shared.open(url)
        }
    }

    /// POST the report to the relay, which files the GitHub issue. The
    /// relay URL and its app key are not secrets; the token that talks
    /// to GitHub lives only on the relay.
    private static let relayURL = URL(string: "https://interviewai-report.nils-effmert.workers.dev")!
    private static let relayKey = "7ccd6eb00745eefae058909f337e07f1"

    private static func fileViaRelay(description: String, version: String, macOS: String, engine: String, screenshot: Data?) async throws -> (Int, URL) {
        var request = URLRequest(url: relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(relayKey, forHTTPHeaderField: "X-Report-Key")
        var payload: [String: Any] = [
            "title": IssueReport.title(description),
            "body": IssueReport.body(description: description, version: version, macOS: macOS, engine: engine),
        ]
        if let screenshot {
            payload["screenshot"] = screenshot.base64EncodedString()
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["number"] as? Int,
              let page = (object["url"] as? String).flatMap(URL.init(string:)) else {
            throw URLError(.badServerResponse)
        }
        return (number, page)
    }
}

/// One Report window, reused, like the Shortcuts and About windows.
@MainActor
enum ReportIssueWindow {
    private static var controller: NSWindowController?

    static func show() {
        if let controller {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Report a bug"
        window.contentView = NSHostingView(rootView: ReportIssueView())
        window.isReleasedWhenClosed = false
        window.center()
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate()
        sizeWindowToContent(window)
    }

    static func close() {
        controller?.window?.close()
    }

    /// Hide or restore the window around a screen capture.
    static func setVisible(_ visible: Bool) {
        guard let window = controller?.window else { return }
        if visible {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }
}
