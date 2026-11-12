import SwiftUI
import InterviewAIKit

/// The ten-second setup shown before a recording starts, rebuilt
/// clean after Hedy's start dialog (Nils's call, 2026-11-12): one
/// stacked card per choice, no section headlines, values with a
/// chevron, Cancel and one ink Start. Until this sheet existed,
/// pressing Start Listening was the whole setup: the saved meeting
/// then took its name from whatever calendar event overlapped,
/// all-day birthdays included, and the summary believed the name.
/// Now the user confirms what the call is, or says it is not an
/// appointment at all, picks the mode and the language, sets audio
/// saving for this session, and can leave one line of context that
/// the answers, the suggestions, and the notes all work from.
struct SessionSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @AppStorage("speech.locale") private var speechLocale = "en-US"
    @AppStorage("answers.language") private var answerLanguage = ""

    @State private var matchedEvent: UpcomingEvent?
    @State private var useEvent = false
    @State private var modeID = ""
    @State private var selectedLocale = ""
    @State private var contextText = ""
    @State private var saveAudio = false
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Start Session")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                rowCard {
                    HStack {
                        Text("Save Session Audio")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Toggle("Save Session Audio", isOn: $saveAudio)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                Text("Only record with everyone's consent. The file stays on this Mac and is deleted with its meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.xs)
            }

            menuRow(value: modeName) {
                ForEach(BuiltInModes.all) { mode in
                    Button(mode.name) { modeID = mode.id }
                }
                if !model.customModes().isEmpty {
                    Divider()
                    ForEach(model.customModes(), id: \.uuid) { custom in
                        Button(custom.name) { modeID = custom.idString }
                    }
                }
            }

            menuRow(value: languageName) {
                ForEach(OnboardingLanguage.all) { language in
                    Button(language.name) { selectedLocale = language.locale }
                }
            }

            if let event = matchedEvent {
                VStack(alignment: .leading, spacing: Space.xs) {
                    menuRow(value: useEvent ? event.title : "Just a call") {
                        Button(event.title) { useEvent = true }
                        Button("Just a call") { useEvent = false }
                    }
                    if useEvent {
                        Text("\(eventTimeText(event))\(event.attendees.isEmpty ? "" : " · with \(event.attendees.prefix(3).joined(separator: ", "))")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Space.xs)
                    }
                }
            } else {
                rowCard {
                    Text("No appointment right now · saved as a call")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            rowCard {
                TextField("What is this about? A name, a topic, a goal", text: $contextText)
                    .textFieldStyle(.plain)
                    .font(.callout)
            }

            Text("Answers and suggestions listen to the other side through this Mac. If the call runs on your phone, the other side will not be heard, and the notes will say that only your side was captured.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: Space.sm) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Start Session") {
                    if !modeID.isEmpty, modeID != model.activeModeID {
                        model.activeModeID = modeID
                    }
                    if let language = OnboardingLanguage.matching(locale: selectedLocale) {
                        speechLocale = language.locale
                        answerLanguage = language.answerLanguage
                    }
                    dismiss()
                    model.session.startPlanned(
                        event: useEvent ? matchedEvent : nil,
                        context: contextText,
                        saveAudio: saveAudio
                    )
                }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
        .background(Surface.canvas)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let now = Date.now
            matchedEvent = CalendarService.event(
                overlappingSessionStart: now.addingTimeInterval(-15 * 60),
                end: now.addingTimeInterval(30 * 60)
            )
            useEvent = matchedEvent != nil
            modeID = model.activeModeID
            selectedLocale = OnboardingLanguage.matching(locale: speechLocale)?.locale ?? "en-US"
            saveAudio = UserDefaults.standard.bool(forKey: "sessionAudio.enabled")
        }
    }

    private var modeName: String {
        if let builtIn = BuiltInModes.all.first(where: { $0.id == modeID }) {
            return builtIn.name
        }
        if let custom = model.customModes().first(where: { $0.idString == modeID }) {
            return custom.name
        }
        return "General"
    }

    private var languageName: String {
        OnboardingLanguage.matching(locale: selectedLocale)?.name ?? "English (US)"
    }

    private func rowCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Surface.controlBorder, lineWidth: 1)
            }
    }

    private func menuRow<Content: View>(value: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            rowCard {
                HStack(spacing: Space.sm) {
                    Text(value)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func eventTimeText(_ event: UpcomingEvent) -> String {
        let time = DateFormatter()
        time.timeStyle = .short
        let day: String
        if Calendar.current.isDateInToday(event.start) { day = "Today" }
        else if Calendar.current.isDateInTomorrow(event.start) { day = "Tomorrow" }
        else {
            let df = DateFormatter()
            df.dateFormat = "EEE d MMM"
            day = df.string(from: event.start)
        }
        return "\(day) · \(time.string(from: event.start))"
    }
}
