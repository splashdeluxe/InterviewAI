import AppKit
import InterviewAIKit
import SwiftUI

/// First-open setup, in the shape of Metaview's permission priming:
/// one card, the three things the app needs, each with its own enable
/// button, and a Continue that unlocks once both transcription
/// permissions are in. Shown once, on the first open; the same
/// switches live on in Settings, Permissions.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var micState = PermissionState.microphone()
    @State private var screenGranted = PermissionState.screenRecordingGranted()
    @State private var calendarState = CalendarService.authorizationText()
    @State private var askedMic = false
    @State private var askedScreen = false
    @State private var askedCalendar = false

    private var calendarGranted: Bool { calendarState == "Granted" }
    private var micGranted: Bool { micState == "Granted" }
    private var canContinue: Bool { micGranted && screenGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Allow InterviewAI to hear and transcribe your calls")
                    .font(.title3.weight(.semibold))
                Text("Three things, asked once. Nothing is captured on its own: listening starts only when you press Start Listening, and transcription runs on this Mac.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                row(title: "Meeting detection",
                    detail: "Finds the meeting you are in and names your saved meetings, with the people who were invited. Read-only: it never changes an event.",
                    granted: calendarGranted,
                    enableLabel: "Enable detection",
                    asked: askedCalendar,
                    pane: "Privacy_Calendars") {
                    askedCalendar = true
                    Task {
                        _ = await CalendarService.requestAccess()
                        calendarState = CalendarService.authorizationText()
                    }
                }
                Divider()
                row(title: "Transcribe my voice",
                    detail: "Hears your side of the call, through your microphone.",
                    granted: micGranted,
                    enableLabel: "Enable microphone",
                    asked: askedMic,
                    pane: "Privacy_Microphone") {
                    askedMic = true
                    Task {
                        _ = await PermissionState.requestMicrophone()
                        micState = PermissionState.microphone()
                    }
                }
                Divider()
                row(title: "Transcribe other people",
                    detail: "Hears the other side, through the call audio. macOS calls this Screen Recording; InterviewAI takes the audio only, never the picture.",
                    granted: screenGranted,
                    enableLabel: "Enable meeting audio",
                    asked: askedScreen,
                    pane: "Privacy_ScreenCapture") {
                    askedScreen = true
                    screenGranted = PermissionState.requestScreenRecording()
                }
            }
            .panelSurface(radius: Radius.card)

            HStack(alignment: .center, spacing: Space.md) {
                Text(canContinue
                     ? "You are set. All three can be changed later in Settings, Permissions."
                     : "Microphone and meeting audio are needed to transcribe a call. Meeting detection is optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.md)
                Button("Skip for now", action: onFinish)
                    .buttonStyle(QuietButtonStyle())
                Button(action: onFinish) {
                    HStack(spacing: Space.xs) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(!canContinue)
            }
        }
        .padding(Space.xl)
        .frame(width: 580)
        .background(Surface.canvas)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        micState = PermissionState.microphone()
        screenGranted = PermissionState.screenRecordingGranted()
        calendarState = CalendarService.authorizationText()
    }

    private func row(title: String, detail: String, granted: Bool, enableLabel: String,
                     asked: Bool, pane: String, enable: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.md)
            if granted {
                HStack(spacing: Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Granted")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: Space.sm) {
                    if asked {
                        Button("Open Settings") { openPane(pane) }
                            .buttonStyle(QuietButtonStyle())
                    }
                    Button(enableLabel, action: enable)
                        .buttonStyle(InkButtonStyle())
                }
            }
        }
        .padding(Space.md)
    }

    private func openPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
