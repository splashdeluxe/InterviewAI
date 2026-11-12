import AppKit
import InterviewAIKit
import SwiftUI

/// First-run setup as a six-step wizard (onboarding v2, Hedy plan
/// phase 3): welcome, language, what you are here for, permissions,
/// your material, and a short tour of the copilot. One question per
/// screen, a progress bar across the top, Skip on every step. The
/// permissions step is the proven 1.10.0 card, logic unchanged, now
/// one step among six. Every answer writes to the same stores the
/// Settings pages own: speech locale, answer language, active mode.
/// Shown for fresh installs only; Help can replay it.
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @State private var step = 0

    @AppStorage("speech.locale") private var speechLocale = "en-US"
    @AppStorage("answers.language") private var answerLanguage = ""
    @State private var pickedLocale = "en-US"
    @State private var goToContext = false

    @State private var micState = PermissionState.microphone()
    @State private var screenGranted = PermissionState.screenRecordingGranted()
    @State private var calendarState = CalendarService.authorizationText()
    @State private var askedMic = false
    @State private var askedScreen = false
    @State private var askedCalendar = false

    private var calendarGranted: Bool { calendarState == "Granted" }
    private var micGranted: Bool { micState == "Granted" }
    private var permissionsReady: Bool { micGranted && screenGranted }
    private var canContinue: Bool {
        OnboardingFlow.canContinue(step: step, micGranted: micGranted, screenGranted: screenGranted)
    }
    private var isLastStep: Bool { step == OnboardingFlow.stepCount - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            progressBar
            stepContent
            Spacer(minLength: 0)
            footer
        }
        .padding(Space.xl)
        .frame(width: 580, height: 620)
        .background(Surface.canvas)
        .onAppear { pickedLocale = speechLocale }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var progressBar: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<OnboardingFlow.stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(height: 4)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: languageStep
        case 2: purposeStep
        case 3: permissionsStep
        case 4: materialStep
        default: teachStep
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: Space.md) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(QuietButtonStyle())
            }
            if step == OnboardingFlow.permissionsStep {
                Text(permissionsReady
                     ? "You are set. All three can be changed later in Settings, Permissions."
                     : "Microphone and meeting audio are needed to transcribe a call. Meeting detection is optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.md)
            Button("Skip for now", action: finish)
                .buttonStyle(QuietButtonStyle())
            Button(action: advance) {
                HStack(spacing: Space.xs) {
                    Text(isLastStep ? "Finish" : "Continue")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(InkButtonStyle())
            .disabled(!canContinue)
        }
    }

    private func advance() {
        if step == 1, let language = OnboardingLanguage.matching(locale: pickedLocale) {
            speechLocale = language.locale
            answerLanguage = language.answerLanguage
        }
        if isLastStep {
            finish()
        } else {
            step += 1
        }
    }

    private func finish() {
        if goToContext { model.sidebar = .context }
        onFinish()
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Surface.ink)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Surface.onInk)
                }
            Text("A copilot for your calls")
                .font(.title2.weight(.semibold))
            Text("InterviewAI listens to your calls, drafts answers you can say out loud, and writes the notes when you hang up. Transcription runs on this Mac. Nothing is captured on its own: listening starts only when you press Start Listening.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ready in about a minute.")
                .foregroundStyle(.secondary)
            Button("I know my way around", action: finish)
                .buttonStyle(QuietButtonStyle())
                .padding(.top, Space.sm)
        }
    }

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            stepTitle("What language are your calls in?",
                      detail: "One pick sets the transcription language and the language your answers are written in. Both can be changed later, separately, in Settings.")
            VStack(spacing: 0) {
                ForEach(Array(OnboardingLanguage.all.enumerated()), id: \.element.id) { index, language in
                    if index > 0 { Divider() }
                    Button {
                        pickedLocale = language.locale
                    } label: {
                        HStack(spacing: Space.md) {
                            Text(language.name)
                                .font(.callout.weight(.medium))
                            Spacer()
                            if pickedLocale == language.locale {
                                Image(systemName: "checkmark")
                                    .font(.callout.weight(.semibold))
                            }
                        }
                        .padding(Space.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .panelSurface(radius: Radius.card)
        }
    }

    private var purposeStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            stepTitle("What are you here for?",
                      detail: "Pick the closest one. It sets your starting mode, so the first call already sounds right. Modes switch any time, and you can build your own.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.sm), GridItem(.flexible(), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(OnboardingPurpose.all) { purpose in
                    Button {
                        model.activeModeID = purpose.modeID
                        step += 1
                    } label: {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(purpose.title)
                                .font(.callout.weight(.semibold))
                            Text(purpose.line)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.md)
                        .panelSurface(radius: Radius.card)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            stepTitle("Allow InterviewAI to hear and transcribe your calls",
                      detail: "Three things, asked once. Nothing is captured on its own: listening starts only when you press Start Listening, and transcription runs on this Mac.")
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
        }
    }

    private var materialStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            stepTitle("Bring your material",
                      detail: "Answers get sharper with your CV and the job description in them, and they never invent what is not there. Add them now, or any time later on the Context page.")
            VStack(spacing: Space.sm) {
                materialRow(symbol: "doc.text", title: "Add my CV",
                            line: "Your experience, in your words. Answers quote it, they do not pad it.")
                materialRow(symbol: "doc.plaintext", title: "Paste a job description",
                            line: "The role you want, so answers aim at it.")
                Button {
                    step += 1
                } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: "clock")
                            .font(.callout.weight(.semibold))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Later")
                                .font(.callout.weight(.semibold))
                            Text("Skip this for now. The Context page is always there.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(Space.md)
                    .panelSurface(radius: Radius.card)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func materialRow(symbol: String, title: String, line: String) -> some View {
        Button {
            goToContext = true
            step += 1
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: symbol)
                    .font(.callout.weight(.semibold))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(Space.md)
            .panelSurface(radius: Radius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var teachStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            stepTitle("Meet your copilot",
                      detail: "Four things worth knowing before the first call. The rest is in Help.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.sm), GridItem(.flexible(), spacing: Space.sm)], spacing: Space.sm) {
                teachPanel(symbol: "rectangle.on.rectangle", title: "The overlay floats over your call",
                           line: "Press ⌘⇧H to show or hide it. Answers land there first, over whatever app the call is in.")
                teachPanel(symbol: "command", title: "Seven answers, one keystroke each",
                           line: "⌘1 answers, ⌘2 clarifies, ⌘3 asks a follow up. The full map is on ⌘/.")
                teachPanel(symbol: "waveform", title: "Auto Answer hears the question",
                           line: "When the other side finishes a real question, a draft starts on its own. Read it, edit it, or ignore it.")
                teachPanel(symbol: "lightbulb", title: "Suggestions arrive quietly",
                           line: "Every couple of minutes the engine offers one coaching tip, filtered hard. Most minutes, it says nothing.")
            }
        }
    }

    private func teachPanel(symbol: String, title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
            Text(title)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(line)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .panelSurface(radius: Radius.card)
    }

    private func stepTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Permissions (the 1.10.0 card, unchanged)

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
