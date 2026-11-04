import AppKit
import SwiftUI
import InterviewAIKit

/// The Settings window (Command-Comma). One tab per topic. There is no
/// account, plan, licence, or store tab, because there is nothing to sell.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .frame(width: 560, height: settingsHeight)
        .noInitialFocus()
    }

    /// Tall enough for the longest page (Providers, with its three
    /// sections) on this screen, so no Settings page has to scroll.
    /// Shorter pages leave plain canvas below the form.
    private var settingsHeight: CGFloat {
        min(760, (NSScreen.main?.visibleFrame.height ?? 900) - 120)
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .providers: ProvidersSettings()
            case .speech: SpeechSettings()
            case .permissions: PermissionsSettings()
            case .help: HelpSettings()
            case .about: AboutSettings()
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, providers, speech, permissions, help, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .speech: "Speech"
        case .permissions: "Permissions"
        case .help: "Help"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .providers: "cpu"
        case .speech: "waveform"
        case .permissions: "lock.shield"
        case .help: "questionmark.circle"
        case .about: "info.circle"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("session.autoAnswer") private var autoAnswer = true
    @AppStorage("overlay.opacity") private var overlayOpacity = 1.0
    @AppStorage("reading.highlightKeywords") private var highlightKeywords = true
    @AppStorage("reading.answerFontSize") private var answerFontSize = 18.0
    @AppStorage("general.showInDock") private var showInDock = true

    var body: some View {
        Section("Live Session") {
            Toggle("Auto Answer", isOn: $autoAnswer)
            Text("When the other side finishes a question, an answer starts on its own. Off means answers wait for ⌘1 to ⌘7 or the ask box.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $overlayOpacity, in: 0.5...1.0) {
                Text("Overlay opacity")
            }
        }
        Section("Phone Display") {
            Toggle("Show the session on my phone", isOn: Binding(
                get: { model.phoneDisplayEnabled },
                set: { model.phoneDisplayEnabled = $0 }
            ))
            if model.phoneDisplayEnabled {
                if let address = model.phoneDisplay.pageAddress {
                    Text("Open this on your phone, on the same Wi-Fi:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.headline)
                        .textSelection(.enabled)
                } else if let problem = model.phoneDisplay.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Starting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("The page shows the live answer, the conversation, and the action buttons, and its taps work like ⌘1 to ⌘7. While this is on, anyone on the same network can open the page, so only use it on a network you trust.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Reading") {
            Toggle("Highlight Keywords", isOn: $highlightKeywords)
            Text("The bold terms and the figures in an answer get a yellow wash, so the point is easy to spot while you talk.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Font Size")
                Slider(value: $answerFontSize, in: 14...24, step: 1)
                Text("\(Int(answerFontSize)) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("The size of the answer text, on the Live page and in the overlay.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Visibility") {
            Toggle("Show in Dock", isOn: $showInDock)
                .onChange(of: showInDock) { _, shown in
                    NSApp.setActivationPolicy(shown ? .regular : .accessory)
                }
            Text("Shows InterviewAI in the Dock and the app switcher. Anyone you share your screen with can see it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show Menu Bar Icon", isOn: Binding(
                get: { model.showMenuBarIcon },
                set: { model.showMenuBarIcon = $0 }
            ))
            Text("Adds an InterviewAI icon to the menu bar, for starting and stopping listening, the overlay, and quitting. Anyone you share your screen with can see it. With the Dock icon and this icon both off, the global hotkeys still reach the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Shortcuts") {
            ForEach(HotkeyCenter.shared.shortcutList, id: \.label) { row in
                HStack {
                    Text(row.label)
                    Spacer()
                    Text(row.combo)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(HotkeyCenter.shared.failures, id: \.self) { failure in
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct ProvidersSettings: View {
    @AppStorage("provider.kind") private var kind = "ollama"
    @AppStorage("provider.baseURL") private var baseURL = "http://localhost:11434"
    @AppStorage("provider.model") private var modelName = "llama3.2:1b"
    @AppStorage("provider.vision") private var vision = false
    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var keySaveFailed = false
    @State private var tavilyDraft = ""
    @State private var tavilySaved = false
    @State private var tavilySaveFailed = false
    @State private var testResult: String?

    var body: some View {
        Section("Model Provider") {
            Picker("Provider", selection: $kind) {
                Text("Ollama (local, no key)").tag("ollama")
                Text("OpenAI-compatible (your key)").tag("openAICompatible")
            }
            .onChange(of: kind) { _, newKind in
                // Swap the defaults when the fields still hold the other
                // provider's defaults, so Test Connection works at once.
                if newKind == "openAICompatible", baseURL == "http://localhost:11434" {
                    baseURL = "https://api.openai.com"
                    modelName = "gpt-4o-mini"
                }
                if newKind == "ollama", baseURL == "https://api.openai.com" {
                    baseURL = "http://localhost:11434"
                    modelName = "llama3.2:1b"
                }
            }
            TextField("Base URL", text: $baseURL)
            TextField("Model", text: $modelName)
            Toggle("This model can read images", isOn: $vision)
            Text("Local Ollama is free and private: pull a model with `ollama pull llama3.2:1b`, or a vision model like `llama3.2-vision`. The 1B model is the fastest local option. Cloud endpoints use your own key and your own bill with that provider. InterviewAI adds nothing on top.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if kind == "openAICompatible" {
            Section("Your API Key") {
                SecureField("API key", text: $keyDraft)
                HStack {
                    Button("Save Key to Keychain") {
                        keySaveFailed = !KeychainStore.set(keyDraft, account: "provider-key")
                        keyDraft = ""
                        keySaved = !keySaveFailed
                    }
                    if keySaved {
                        Text("Saved").foregroundStyle(.secondary)
                    }
                    if keySaveFailed {
                        Text("Save failed. The key was not stored.").foregroundStyle(.red)
                    }
                }
            }
        }
        Section("Web Search (optional)") {
            SecureField("Tavily API key", text: $tavilyDraft)
            HStack {
                Button("Save Key to Keychain") {
                    tavilySaveFailed = !KeychainStore.set(tavilyDraft, account: "tavily-key")
                    tavilyDraft = ""
                    tavilySaved = !tavilySaveFailed
                }
                if tavilySaved {
                    Text("Saved").foregroundStyle(.secondary)
                }
                if tavilySaveFailed {
                    Text("Save failed. The key was not stored.").foregroundStyle(.red)
                }
            }
            Text("Only used by Company Intel on the Profile page, to add live web results. Without a key, Company Intel works from the job description alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Connection") {
            Button("Test Connection") {
                testResult = "Testing"
                let config = ProviderSettings.config()
                let apiKey = ProviderSettings.apiKey
                Task {
                    do {
                        let answer = try await Brain.complete(
                            config: config, apiKey: apiKey,
                            system: "You reply with one word.",
                            user: "Reply with the word ready."
                        )
                        testResult = "Works. The model answered: \(answer.prefix(60))"
                    } catch {
                        testResult = "Failed: \(error.localizedDescription)"
                    }
                }
            }
            if let testResult {
                Text(testResult)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SpeechSettings: View {
    @AppStorage("speech.locale") private var locale = "en-US"
    @AppStorage("transcription.engine") private var engine = "parakeetUltra"
    @AppStorage("transcription.whisperModel") private var whisperModel = "large-v3-v20240930_626MB"
    @AppStorage("transcription.translateTo") private var translateTo = ""
    @AppStorage("transcription.diarize") private var diarize = true
    @State private var modelState = ""
    @State private var loadingModel = false
    @State private var parakeetState = ""
    @State private var loadingParakeet = false

    var body: some View {
        Section("Transcription") {
            Picker("Engine", selection: $engine) {
                Text("Parakeet Ultra (local, fastest)").tag("parakeetUltra")
                Text("Whisper (local, stronger)").tag("whisper")
                Text("Apple Speech").tag("appleSpeech")
            }
            Picker("Language", selection: $locale) {
                Text("English (US)").tag("en-US")
                Text("English (UK)").tag("en-GB")
                Text("German").tag("de-DE")
                Text("Russian").tag("ru-RU")
                Text("Indonesian").tag("id-ID")
                Text("Spanish").tag("es-ES")
            }
            if engine == "parakeetUltra" {
                HStack(spacing: Space.sm) {
                    Button("Download / Load Model") {
                        loadingParakeet = true
                        parakeetState = "Loading. The first run downloads about 650 MB."
                        Task {
                            do {
                                try await ParakeetRuntime.shared.prepare()
                                parakeetState = "Model ready. Parakeet Ultra is loaded."
                            } catch {
                                parakeetState = "Failed: \(error.localizedDescription)"
                            }
                            loadingParakeet = false
                        }
                    }
                    .disabled(loadingParakeet)
                    if loadingParakeet { ProgressView().controlSize(.small) }
                    if !parakeetState.isEmpty {
                        Text(parakeetState).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Parakeet Ultra is Moondream's retrain of NVIDIA's Parakeet v3, run on the Neural Engine through FluidAudio. It works out the language itself across 25 European languages, English, German and Russian among them. Indonesian is not one of them: for Bahasa, pick Whisper. It needs no Speech Recognition permission and no network after the one-time download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if engine == "whisper" {
                Picker("Whisper model", selection: $whisperModel) {
                    Text("Large v3 Turbo, compressed (626 MB)").tag("large-v3-v20240930_626MB")
                    Text("Small (about 500 MB)").tag("small")
                    Text("Base (about 150 MB, fastest)").tag("base")
                }
                HStack(spacing: Space.sm) {
                    Button("Download / Load Model") {
                        loadingModel = true
                        modelState = "Loading. The first run downloads the model."
                        Task {
                            do {
                                try await WhisperRuntime.shared.prepare(model: whisperModel)
                                modelState = "Model ready."
                            } catch {
                                modelState = "Failed: \(error.localizedDescription)"
                            }
                            loadingModel = false
                        }
                    }
                    .disabled(loadingModel)
                    if loadingModel { ProgressView().controlSize(.small) }
                    if !modelState.isEmpty {
                        Text(modelState).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Whisper runs on this Mac with WhisperKit, in chunks cut on pauses, so lines land a few seconds after they are spoken. It needs no Speech Recognition permission and no network after the one-time model download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if engine == "appleSpeech" {
                Text("Transcription runs on this Mac with Apple Speech, for both channels. Audio is never recorded to disk and never sent anywhere. On-device recognition is used when the language supports it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Translation and Speakers") {
            Picker("Translate transcripts to", selection: $translateTo) {
                Text("Off").tag("")
                ForEach(TranslationPrompts.languages, id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            Text("Each finished line is translated by your provider as it lands: the local model by default, or your own key's endpoint if you set one. The translation shows as the line, the original stays under it, and saved meetings keep both. Answers still work from the original wording.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Tell speakers apart on the other side", isOn: $diarize)
            Text("When a call ends, the other side's audio is checked on this Mac for different voices, and the saved transcript labels them Speaker 1, Speaker 2, and so on. The first time, a small model downloads once. Audio is never saved to disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PermissionsSettings: View {
    @State private var screenState = "Checking"
    @State private var speechState = PermissionState.speech()
    @State private var micState = PermissionState.microphone()
    @State private var calendarState = CalendarService.authorizationText()

    var body: some View {
        Section("Permissions") {
            permissionRow("Microphone", state: micState, pane: "Privacy_Microphone") {
                Task {
                    _ = await PermissionState.requestMicrophone()
                    micState = PermissionState.microphone()
                }
            }
            permissionRow("Speech Recognition", state: speechState, pane: "Privacy_SpeechRecognition") {
                Task {
                    _ = await PermissionState.requestSpeech()
                    speechState = PermissionState.speech()
                }
            }
            permissionRow("Screen Recording (system audio)", state: screenState, pane: "Privacy_ScreenCapture") {
                Task { screenState = await PermissionState.screenRecording() }
            }
            permissionRow("Calendar (read-only)", state: calendarState, pane: "Privacy_Calendars") {
                Task {
                    _ = await CalendarService.requestAccess()
                    calendarState = CalendarService.authorizationText()
                }
            }
            Text("Calendar is read-only: upcoming meetings on the Live page, one-click starts, and event names on saved meetings. InterviewAI never creates or changes an event.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Screen Recording is what lets InterviewAI hear the other side of the call. InterviewAI is a normal visible app: no hidden mode, no process disguise.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("macOS ties this grant to the exact binary, so a fresh build can read Not granted even when an older build is ticked in System Settings. The check here never asks by itself; listening asks at most once per launch. A stable signing identity keeps the grant across rebuilds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { screenState = await PermissionState.screenRecording() }
    }

    private func permissionRow(_ name: String, state: String, pane: String, request: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(state)
                .foregroundStyle(state == "Granted" ? Color.secondary : Color.orange)
            Button("Ask", action: request)
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

struct HelpSettings: View {
    @State private var setupTest = SetupTest()

    var body: some View {
        Section("Setup Test") {
            Text("Checks the chain an answer depends on: the model must answer 1 plus 1 correctly through the real prompt path, the speech model must load, and the permissions must be in place. Run it before a call you care about.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(setupTest.isRunning ? "Testing…" : "Run Setup Test") {
                Task { await setupTest.run() }
            }
            .disabled(setupTest.isRunning)
            ForEach(setupTest.lines) { line in
                Label(line.text, systemImage: line.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(line.ok ? Color.green : Color.red)
            }
        }
        Section("How It Works") {
            Text("1. Add your resume and the job description on the Context page.")
            Text("2. Pick a mode. Looking for Work fits most interviews.")
            Text("3. Start Listening on the Live page, or show the overlay with ⌘⇧H and start there.")
            Text("4. Answers stream into the overlay. ⌘1 to ⌘7 run the action row.")
            Text("5. Stop when the call ends. The meeting is saved with a summary and a follow-up draft.")
        }
        Section("Privacy") {
            Text("Transcription is on-device. Context files and meetings stay in a local database. The only data that leaves this Mac is the prompt sent to the provider you picked, with your key or to your local model.")
        }
    }
}

struct AboutSettings: View {
    var body: some View {
        Section("InterviewAI") {
            LabeledContent("Version", value: UpdateChecker.currentVersion)
            LabeledContent("Price", value: "Free. No account, licence, trial, quota, or store.")
            LabeledContent("Updates", value: "App menu, About InterviewAI, then Check for Updates.")
            Text("An original Swift app by Nils Effmert, written from scratch. It contains no third-party app code, text, prompts, icons, or branding.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
