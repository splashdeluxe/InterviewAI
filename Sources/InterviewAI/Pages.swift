import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import InterviewAIKit

// MARK: Live

struct LivePage: View {
    @Environment(AppModel.self) private var model
    @State private var upcomingEvents: [UpcomingEvent] = []
    @State private var calendarState = CalendarService.authorizationText()

    var body: some View {
        let session = model.session
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                StatusDot(listening: session.isListening)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.isListening ? "Listening" : "Ready")
                        .font(.callout.weight(.semibold))
                    Text(session.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                modePicker
                Toggle("Auto Answer", isOn: Binding(
                    get: { session.autoAnswer },
                    set: { session.autoAnswer = $0 }
                ))
                .toggleStyle(.switch)
                .help("Answer on your own when the other side finishes a question")
                Button("Overlay", systemImage: "macwindow.on.rectangle") { model.overlay.toggle() }
                    .buttonStyle(QuietButtonStyle())
                    .help("Show or hide the floating overlay (⌘⇧H)")
                Button(session.isListening ? "Stop" : "Start Listening", systemImage: session.isListening ? "stop.circle" : "waveform") {
                    session.toggle()
                }
                .buttonStyle(InkButtonStyle())
                .help("Start or stop listening (⌘⇧L)")
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.md)

            calendarBar
                .background(Surface.panel)
                .overlay(alignment: .top) { Rectangle().fill(Surface.hairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Surface.hairline).frame(height: 1) }

            HSplitView {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Transcript")
                        .font(.headline)
                    OverlayTranscriptList()
                }
                .padding(Space.md)
                .panelSurface()
                .padding(Space.sm)
                .frame(minWidth: 280)

                VStack(alignment: .leading, spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: Binding(get: { session.notes }, set: { session.notes = $0 }))
                            .font(.body)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(Space.md)
                    .panelSurface()
                    .frame(minHeight: 140)

                    HStack(spacing: 0) {
                        AnswerRail(active: session.isAnswering || !session.answer.isEmpty)
                        VStack(alignment: .leading, spacing: Space.sm) {
                            HStack(spacing: Space.sm) {
                                Text("Answer")
                                    .font(.headline)
                                if session.isAnswering {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            if let error = session.answerError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ScrollView {
                                if session.answer.isEmpty {
                                    Text("Answers also appear here and in the overlay.")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    AnswerTextView(text: session.answer)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(Space.md)
                    }
                    .panelSurface()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .frame(minHeight: 160)
                }
                .padding(Space.sm)
                .frame(minWidth: 280)
            }
        }
        .navigationTitle("Live")
        .task { reloadCalendar() }
    }

    // MARK: Calendar

    private func reloadCalendar() {
        calendarState = CalendarService.authorizationText()
        upcomingEvents = CalendarService.upcoming()
    }

    private var calendarBar: some View {
        HStack(spacing: Space.md) {
            Text("Up next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if calendarState == "Granted" {
                if upcomingEvents.isEmpty {
                    Text("No meetings in the next 7 days.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.sm) {
                            ForEach(upcomingEvents.prefix(6)) { event in
                                Button {
                                    model.session.start(event: event)
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.title)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        Text(eventTimeText(event))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(ChipButtonStyle())
                                .disabled(model.session.isListening)
                                .help("Start listening for this meeting")
                            }
                        }
                    }
                }
                Button("Refresh", systemImage: "arrow.clockwise") { reloadCalendar() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietButtonStyle())
                    .help("Reload the calendar")
            } else if calendarState == "Not asked" {
                Text("See your meetings here and start one with a click.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Connect Calendar") {
                    Task {
                        _ = await CalendarService.requestAccess()
                        reloadCalendar()
                    }
                }
                .buttonStyle(QuietButtonStyle())
            } else {
                Text("Calendar access is off. Turn it on under Settings, Permissions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.sm)
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

    private var modePicker: some View {
        Menu {
            ForEach(BuiltInModes.all) { mode in
                Button(mode.name) { model.activeModeID = mode.id }
            }
            if !model.customModes().isEmpty {
                Divider()
                ForEach(model.customModes(), id: \.uuid) { custom in
                    Button(custom.name) { model.activeModeID = custom.idString }
                }
            }
        } label: {
            Label(model.activeMode().definition.name, systemImage: "person.wave.2")
        }
        .help("Switch the active mode")
    }
}

/// One transcript line: who spoke, then the line. When a translation
/// exists it is the line, with the original in small type under it.
struct TranscriptRow: View {
    let segment: TranscriptSegment
    var font: Font = .body

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Text(segment.speakerName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(segment.channel == "me" ? Palette.accentText : .secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.displayText)
                    .font(font)
                    .foregroundStyle(segment.isFinal ? .primary : .secondary)
                    .textSelection(.enabled)
                if segment.translatedText != nil {
                    Text(segment.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// A transcript that runs downward and follows the newest line as it
/// lands, so the latest words are always readable, and stays scrollable:
/// scroll up and it leaves you reading until you come back to the bottom.
struct AutoScrollTranscript: View {
    let segments: [TranscriptSegment]
    var font: Font = .body
    var spacing: CGFloat = Space.sm
    var emptyText: String? = nil
    @State private var atBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: spacing) {
                    ForEach(segments) { segment in
                        TranscriptRow(segment: segment, font: font)
                    }
                    if segments.isEmpty {
                        if let emptyText {
                            Text(emptyText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ContentUnavailableView(
                                "Nothing Heard Yet",
                                systemImage: "waveform.slash",
                                description: Text("Start listening. Both sides of the call will appear here, transcribed on this Mac.")
                            )
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("transcript-bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { proxy.scrollTo("transcript-bottom", anchor: .bottom) }
            .onChange(of: segments.count) { _, _ in follow(proxy) }
            .onChange(of: segments.last?.displayText) { _, _ in follow(proxy) }
        }
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard atBottom else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo("transcript-bottom", anchor: .bottom)
        }
    }
}

/// Transcript lines, shared shape with the overlay.
struct OverlayTranscriptList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AutoScrollTranscript(segments: model.session.displaySegments)
    }
}

// MARK: Meetings

struct MeetingsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var search = ""
    @State private var tab = "Transcript"

    private var visible: [Meeting] {
        guard !search.isEmpty else { return meetings }
        let query = search.lowercased()
        return meetings.filter {
            $0.title.lowercased().contains(query)
                || TranscriptSegment.plainText($0.segments).lowercased().contains(query)
                || $0.notes.lowercased().contains(query)
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(visible, selection: $model.selectedMeeting) { meeting in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(meeting.title)
                        .lineLimit(1)
                    Text(meeting.startedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(meeting.durationSeconds / 60)) min · \(meeting.modeName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(meeting.id)
                .contextMenu {
                    Button("Delete", role: .destructive) { context.delete(meeting) }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            .searchable(text: $search, prompt: "Search meetings")
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView("No Meetings", systemImage: "clock.arrow.circlepath",
                                           description: Text("Finished calls land here with their transcript and summary."))
                }
            }
        } detail: {
            detail
        }
        .navigationTitle("Meetings")
    }

    @ViewBuilder
    private var detail: some View {
        if let meeting = meetings.first(where: { $0.id == model.selectedMeeting }) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(meeting.title).font(.title3.weight(.semibold))
                        Text("\(meeting.modeName) · \(Int(meeting.durationSeconds / 60)) min")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let event = CalendarService.event(id: meeting.eventID) {
                            Label("Calendar: \(event.calendarName)", systemImage: "calendar.badge.checkmark")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Copy Summary") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(meeting.summary, forType: .string)
                    }
                    .disabled(meeting.summary.isEmpty)
                }
                Picker("View", selection: $tab) {
                    Text("Transcript").tag("Transcript")
                    Text("Notes").tag("Notes")
                    Text("Summary").tag("Summary")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case "Notes":
                    TextEditor(text: Binding(get: { meeting.notes }, set: { meeting.notes = $0 }))
                        .font(.body)
                case "Summary":
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            Text(meeting.summary.isEmpty ? "No summary yet. It is written when the call stops, if a model is reachable." : meeting.summary)
                                .textSelection(.enabled)
                            if !meeting.followUp.isEmpty {
                                Text("Follow-Up Draft").font(.headline)
                                Text(meeting.followUp)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                default:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Space.sm) {
                            ForEach(meeting.segments) { segment in
                                TranscriptRow(segment: segment)
                            }
                        }
                    }
                }
            }
            .padding(Space.margin)
        } else {
            ContentUnavailableView("No Meeting Selected", systemImage: "sidebar.right")
        }
    }
}

// MARK: Modes

struct ModesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var newName = ""

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Modes").font(.headline)
                ForEach(BuiltInModes.all) { mode in
                    modeRow(id: mode.id, name: mode.name, builtIn: true)
                }
                ForEach(model.customModes(), id: \.uuid) { custom in
                    modeRow(id: custom.idString, name: custom.name, builtIn: false)
                }
                Divider()
                HStack {
                    TextField("New mode name", text: $newName)
                    Button("Add Mode") {
                        let custom = CustomMode(name: newName.isEmpty ? "My Mode" : newName, promptText: "You help me. Keep answers short and concrete.")
                        context.insert(custom)
                        try? context.save()
                        model.activeModeID = custom.idString
                        newName = ""
                    }
                }
                Spacer()
            }
            .padding(Space.md)
            .frame(minWidth: 220)

            modeDetail
                .frame(minWidth: 320)
        }
        .navigationTitle("Modes")
    }

    private func modeRow(id: String, name: String, builtIn: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            if model.activeModeID == id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.accentText)
            } else {
                Button("Use") { model.activeModeID = id }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.sm)
        .background(model.activeModeID == id ? Surface.inset : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    @ViewBuilder
    private var modeDetail: some View {
        let active = model.activeMode()
        VStack(alignment: .leading, spacing: Space.md) {
            Text(active.definition.name).font(.title3.weight(.semibold))
            Text("Prompt").font(.headline)
            if let custom = model.customModes().first(where: { $0.idString == active.definition.id }) {
                TextEditor(text: Binding(get: { custom.promptText }, set: { custom.promptText = $0 }))
                    .font(.body)
                    .frame(minHeight: 120)
                Button("Delete This Mode", role: .destructive) {
                    context.delete(custom)
                    try? context.save()
                    model.activeModeID = "general"
                }
            } else {
                ScrollView {
                    Text(active.definition.prompt)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.sm)
                }
                .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(minHeight: 80)
                Text("Built-in prompts are fixed. Duplicate the idea as your own mode to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Custom Context for This Mode").font(.headline)
            TextEditor(text: Binding(
                get: { model.activeMode().context },
                set: { model.setModeContext($0, forModeID: model.activeModeID) }
            ))
            .font(.body)
            Text("Salary bands, crib notes, names, anything the answers should know in this mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Space.margin)
    }
}

// MARK: Context

struct ContextPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \ContextFile.createdAt) private var files: [ContextFile]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Context").font(.title3.weight(.semibold))
                    Text("Files that ground your answers. Pinned files go into every answer. Others are picked by how well they match the question.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add File", systemImage: "plus") { addFile() }
                    .buttonStyle(InkButtonStyle())
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            List(files) { file in
                HStack(spacing: Space.md) {
                    Image(systemName: "doc.text")
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(file.name)
                        Text("\(file.text.split(whereSeparator: \.isWhitespace).count) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Resume") { setKind("resume", for: file) }
                        Button("Job description") { setKind("job", for: file) }
                        Button("Notes") { setKind("notes", for: file) }
                        Button("General") { setKind("general", for: file) }
                    } label: {
                        Text(kindTitle(file.kind))
                    }
                    .fixedSize()
                    .help("What this file is. The Profile page pickers only offer files of the right kind.")
                    Toggle("Pinned", isOn: Binding(get: { file.isPinned }, set: { file.isPinned = $0 }))
                        .toggleStyle(.switch)
                    Button("Remove", role: .destructive) { context.delete(file) }
                        .controlSize(.small)
                }
                .padding(.vertical, Space.xs)
            }
            .overlay {
                if files.isEmpty {
                    ContentUnavailableView("No Context Yet", systemImage: "doc.text",
                                           description: Text("Add your resume and the job description. Answers will use them right away."))
                }
            }
        }
        .padding(Space.margin)
        .navigationTitle("Context")
    }

    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "resume": return "Resume"
        case "job": return "Job description"
        case "notes": return "Notes"
        default: return "General"
        }
    }

    private func setKind(_ kind: String, for file: ContextFile) {
        file.kind = kind
        if kind == "resume" || kind == "job" { file.isPinned = true }
        try? context.save()
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.text, UTType.plainText, UTType.pdf, UTType(filenameExtension: "md")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text: String
            if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url), let string = document.string else {
                    error = "That PDF has no readable text."
                    return
                }
                text = string
            } else {
                text = try String(contentsOf: url, encoding: .utf8)
            }
            model.addContextFile(name: url.lastPathComponent, text: text)
            error = nil
        } catch {
            self.error = "Could not read that file as text. (\(error.localizedDescription))"
        }
    }
}

// MARK: Ask

struct AskPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @Query private var files: [ContextFile]
    @State private var question = ""
    @State private var answer = ""
    @State private var sources: [String] = []
    @State private var isAsking = false
    @State private var askError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Ask").font(.title3.weight(.semibold))
            Text("Ask across your past meetings and context files. Everything is searched on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("What did we agree about the salary band?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(ask)
                Button("Ask", systemImage: "paperplane") { ask() }
                    .buttonStyle(InkButtonStyle())
                    .disabled(question.isEmpty || isAsking)
            }
            if let askError {
                Text(askError).foregroundStyle(.red).font(.callout)
            }
            ScrollView {
                Text(answer.isEmpty ? "The answer will appear here." : answer)
                    .foregroundStyle(answer.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.md)
            }
            .panelSurface()
            .frame(minHeight: 160)
            if !sources.isEmpty {
                Text("Sources: \(sources.joined(separator: " · "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isAsking { ProgressView().controlSize(.small) }
        }
        .padding(Space.margin)
        .navigationTitle("Ask")
    }

    private func ask() {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return }
        isAsking = true
        askError = nil
        answer = ""
        sources = []

        // Rank meetings and files on the Mac, then send the best of each.
        let meetingDocs = meetings.map { (name: $0.title, text: TranscriptSegment.plainText($0.segments) + "\n" + $0.summary, pinned: false) }
        let fileDocs = files.map { (name: $0.name, text: $0.text, pinned: $0.isPinned) }
        let bestMeetings = ContextRanker.rank(documents: meetingDocs, query: asked).prefix(3)
        let bestFiles = ContextRanker.rank(documents: fileDocs, query: asked).prefix(3)
        sources = (bestMeetings.map(\.name) + bestFiles.map(\.name))
        var contextText = ""
        for doc in bestMeetings { contextText += "From meeting \(doc.name):\n\(doc.text.prefix(4_000))\n\n" }
        for doc in bestFiles { contextText += "From \(doc.name):\n\(doc.text.prefix(4_000))\n\n" }
        if contextText.isEmpty { contextText = "(Nothing in the meetings or files matches. Say so if the answer is not covered.)" }

        let config = ProviderSettings.config()
        let apiKey = ProviderSettings.apiKey
        Task {
            do {
                for try await piece in Brain.stream(
                    config: config, apiKey: apiKey,
                    system: "You answer questions about the user's own meetings and files. Use only the material given. Name the meeting or file a fact came from.",
                    user: "Material:\n\(contextText)\n\nQuestion: \(asked)",
                    imageBase64: nil
                ) {
                    answer += piece
                }
            } catch {
                askError = error.localizedDescription
            }
            isAsking = false
        }
    }
}
