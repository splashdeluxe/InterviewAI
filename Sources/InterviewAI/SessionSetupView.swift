import SwiftUI
import InterviewAIKit

/// The ten-second setup shown before a recording starts. Until this
/// sheet existed, pressing Start Listening was the whole setup: the
/// saved meeting then took its name from whatever calendar event
/// overlapped, all-day birthdays included, and the summary believed
/// the name. Now the user confirms what the call is, or says it is
/// not an appointment at all, picks the mode, and can leave one line
/// of context that the answers, the suggestions, and the notes all
/// work from. Hedy asks for the same thirty seconds before a session,
/// for the same reason.
struct SessionSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var matchedEvent: UpcomingEvent?
    @State private var useEvent = false
    @State private var modeID = ""
    @State private var contextText = ""
    @State private var saveAudio = false
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Set up this recording")
                    .font(.title3.weight(.semibold))
                Text("Ten seconds now, so the answers, the suggestions, and the notes land on the right call.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("What is this?")
                    .font(.headline)
                if let event = matchedEvent {
                    choiceRow(
                        selected: useEvent,
                        title: event.title,
                        detail: "\(eventTimeText(event))\(event.attendees.isEmpty ? "" : " · with \(event.attendees.prefix(3).joined(separator: ", "))")",
                        action: { useEvent = true }
                    )
                    choiceRow(
                        selected: !useEvent,
                        title: "Not an appointment",
                        detail: "Just a call. It is saved under its own name, with no calendar event attached.",
                        action: { useEvent = false }
                    )
                } else {
                    Text("No appointment is on right now. This will be saved as a call, with no calendar event attached.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: Space.md) {
                Text("Mode")
                    .font(.headline)
                Picker("Mode", selection: $modeID) {
                    ForEach(BuiltInModes.all) { mode in
                        Text(mode.name).tag(mode.id)
                    }
                    if !model.customModes().isEmpty {
                        ForEach(model.customModes(), id: \.uuid) { custom in
                            Text(custom.name).tag(custom.idString)
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Who or what is it about?")
                    .font(.headline)
                TextField("Call with Alan", text: $contextText)
                    .textFieldStyle(.roundedBorder)
                Text("Optional. One line is enough: a name, a topic, a goal. It also names the saved meeting when no appointment does.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Toggle("Save the audio with the meeting", isOn: $saveAudio)
                    .toggleStyle(.switch)
                Text("Only record with everyone's consent. The file stays on this Mac and is deleted with its meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Answers and suggestions listen to the other side through this Mac. If the call runs on your phone, the other side will not be heard, and the notes will say that only your side was captured.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: Space.sm) {
                Button("Start without setup") {
                    dismiss()
                    model.session.toggle()
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                Button("Start Listening") {
                    if !modeID.isEmpty, modeID != model.activeModeID {
                        model.activeModeID = modeID
                    }
                    dismiss()
                    model.session.startPlanned(
                        event: useEvent ? matchedEvent : nil,
                        context: contextText,
                        saveAudio: saveAudio
                    )
                }
                .buttonStyle(InkButtonStyle())
            }
        }
        .padding(Space.xl)
        .frame(width: 540)
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
            saveAudio = UserDefaults.standard.bool(forKey: "sessionAudio.enabled")
        }
    }

    private func choiceRow(selected: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.sm) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Palette.accent : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(Space.sm)
            .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(selected ? Palette.accent.opacity(0.5) : Surface.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
