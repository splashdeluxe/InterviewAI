import AppKit
import AVFoundation
import CoreMedia
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
    @AppStorage("sessionAudio.enabled") private var saveSessionAudio = false
    @AppStorage("live.answerLayout") private var answerLayoutRaw = AnswerLayout.balanced.rawValue

    /// How the page splits between transcript and answer, from the
    /// menu in the Answer header: Balanced, Answer Focus, Full Width.
    private var layout: AnswerLayout { AnswerLayout(rawValue: answerLayoutRaw) ?? .balanced }

    var body: some View {
        let session = model.session
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                StatusDot(listening: session.isListening && !session.isPaused)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.isPaused ? "Paused" : session.isListening ? "Listening" : "Ready")
                        .font(.callout.weight(.semibold))
                    Text(session.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if session.audioRecordingActive && !session.isPaused {
                        Label("Recording audio", systemImage: "record.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                modePicker
                Toggle("Auto Answer", isOn: Binding(
                    get: { session.autoAnswer },
                    set: { session.autoAnswer = $0 }
                ))
                .toggleStyle(.switch)
                .help("Answer on your own when the other side finishes a question")
                Toggle("Save Audio", isOn: $saveSessionAudio)
                    .toggleStyle(.switch)
                    .help("Save each session's audio with its meeting. Only record with everyone's consent.")
                Button("Overlay", systemImage: "macwindow.on.rectangle") { model.overlay.toggle() }
                    .buttonStyle(QuietButtonStyle())
                    .help("Show or hide the floating overlay (⌘⇧H)")
                Button(session.isListening ? "Stop" : "Start Listening", systemImage: session.isListening ? "stop.circle" : "waveform") {
                    if session.isListening {
                        // Stop opens the Session Controls: end and
                        // save, pause where it stands, or delete.
                        SessionControlsWindow.show(session: session, quitMode: false)
                    } else {
                        // Setup first: what is this call, is it an
                        // appointment or not, which mode, save the
                        // audio. The sheet is what keeps a random call
                        // from being saved as a birthday.
                        session.setupRequested = true
                    }
                }
                .buttonStyle(InkButtonStyle())
                .help("Start or stop listening (⌘⇧L)")
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.md)

            if session.isListening, let warning = session.otherSideWarning {
                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.sm)
                .background(Color.orange.opacity(0.08))
            }

            calendarBar
                .background(Surface.panel)
                .overlay(alignment: .top) { Rectangle().fill(Surface.hairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Surface.hairline).frame(height: 1) }
                .sheet(isPresented: Binding(
                    get: { session.setupRequested },
                    set: { session.setupRequested = $0 }
                )) {
                    SessionSetupView()
                }

            GeometryReader { geo in
                HStack(spacing: 0) {
                    if layout.showsTranscript {
                    VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        Text("Transcript")
                            .font(.headline)
                        Spacer()
                        Button("Copy Transcript", systemImage: "doc.on.doc") {
                            copyText(TranscriptSegment.plainText(session.finalSegments))
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(QuietButtonStyle())
                        .disabled(session.finalSegments.isEmpty)
                        .help("Copy the whole transcript")
                        Button("Export Transcript", systemImage: "square.and.arrow.up") {
                            saveTextFile(
                                TranscriptExport.markdown(title: session.meetingTitle, date: session.startedAt ?? Date.now, attendees: session.linkedEvent?.attendees ?? [], location: session.linkedEvent?.location ?? "", segments: session.finalSegments, summary: ""),
                                fileName: TranscriptExport.fileName(title: session.meetingTitle, date: session.startedAt ?? Date.now)
                            )
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(QuietButtonStyle())
                        .disabled(session.finalSegments.isEmpty)
                        .help("Export the transcript as a markdown file")
                    }
                    OverlayTranscriptList()
                    }
                    .padding(Space.md)
                    .panelSurface()
                    .padding(Space.sm)
                    .frame(width: max(240, geo.size.width * layout.transcriptFraction))
                    Divider()
                    }

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
                                Spacer()
                                Menu {
                                    ForEach(AnswerLayout.allCases, id: \.rawValue) { option in
                                        Button {
                                            answerLayoutRaw = option.rawValue
                                        } label: {
                                            if option == layout {
                                                Label(option.label, systemImage: "checkmark")
                                            } else {
                                                Text(option.label)
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "rectangle.split.2x1")
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .help("Answer layout: Balanced, Answer Focus, or Full Width")
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
                                    AnswerTextView(text: session.answer, streaming: session.isAnswering)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(Space.md)
                    }
                    .panelSurface()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .frame(minHeight: 160)

                    if !session.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Suggestions")
                                .font(.headline)
                            // Staggering: suggestion rows arrive
                            // one after another by index.
                            ForEach(Array(session.suggestions.enumerated()), id: \.offset) { index, tip in
                                SuggestionRow(tip: tip)
                                    .staggered(index: index)
                            }
                        }
                        .padding(Space.md)
                        .panelSurface()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Space.sm)
                .frame(maxWidth: .infinity)
                }
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
                            // Staggering: the next meetings arrive
                            // one after another by index, not all
                            // in unison.
                            ForEach(Array(upcomingEvents.prefix(6).enumerated()), id: \.element.id) { index, event in
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
                                .staggered(index: index)
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
/// One automatic suggestion as a quiet row: kind tag, the line
/// itself, and the short why under it. Used on the Live page while a
/// session runs and again in the meeting it saved into.
struct SuggestionRow: View {
    let tip: Suggestion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped on appear, so the leading tag can do its bounce.
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            // Secondary action: the row's leading element is its
            // kind tag (the row carries no icon), so the tag does
            // the bounce — it winds up at the anticipation scale
            // and settles on the rubber-band spring, delayed a
            // beat behind the row's own staggered arrival, as a
            // small flourish backing up the main content.
            Text(tip.kind.tag)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
                .scaleEffect(appeared || reduceMotion ? 1 : CGFloat(MotionSpec.anticipationScale), anchor: .leading)
                .animation(
                    reduceMotion
                        ? Motion.contentSwap(reduceMotion: true)
                        : Motion.rubberBand.delay(MotionSpec.secondaryActionDelay),
                    value: appeared
                )
                .onAppear { appeared = true }
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.text)
                    .font(.callout)
                if !tip.why.isEmpty {
                    Text(tip.why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TranscriptRow: View {
    let segment: TranscriptSegment
    var font: Font = .body

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Text(segment.speakerName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(segment.channel == "me" ? Palette.accentText : .secondary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
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

/// A generated document (profile section, summary, follow-up) shown
/// with its markdown marks turned into shape: headings read as
/// headings, bullets as bullets, and inline bold renders bold. The
/// stored text keeps its marks; only the display cleans up.
struct DocTextView: View {
    let text: String
    var font: Font = .callout

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(MarkdownLite.lines(text).enumerated()), id: \.offset) { _, line in
                switch line.kind {
                case .heading:
                    Text(inline(line.text))
                        .font(font.weight(.semibold))
                        .padding(.top, Space.xs)
                case .bullet:
                    HStack(alignment: .top, spacing: Space.xs) {
                        Text("•")
                        Text(inline(line.text))
                    }
                    .font(font)
                case .paragraph:
                    Text(inline(line.text))
                        .font(font)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline markdown (bold, italic) rendered; a line the parser
    /// rejects shows as plain text instead of not at all.
    private func inline(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }
}

/// The whole transcript as ONE selectable text. Each line used to be
/// its own Text view, so a selection could never span more than one
/// line and copying a passage meant copying line by line. As a single
/// attributed string the reader can mark any stretch, across speakers,
/// and copy it in one go.
struct TranscriptBlock: View {
    let segments: [TranscriptSegment]
    var fontSize: CGFloat = 14

    var body: some View {
        Text(Self.attributed(segments: segments, fontSize: fontSize))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func attributed(segments: [TranscriptSegment], fontSize: CGFloat) -> AttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 7
        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let nameColor: NSColor = segment.channel == "me" ? .controlAccentColor : .secondaryLabelColor
            let name = NSAttributedString(string: "\(segment.speakerName): ", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: nameColor,
                .paragraphStyle: paragraph,
            ])
            let bodyColor: NSColor = segment.isFinal ? .labelColor : .secondaryLabelColor
            let body = NSAttributedString(string: segment.displayText, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: bodyColor,
                .paragraphStyle: paragraph,
            ])
            result.append(name)
            result.append(body)
        }
        return AttributedString(result)
    }
}

/// A transcript that runs downward and follows the newest line as it
/// lands, so the latest words are always readable, and stays scrollable:
/// scroll up and it leaves you reading until you come back to the bottom.
struct AutoScrollTranscript: View {
    let segments: [TranscriptSegment]
    var fontSize: CGFloat = 14
    var emptyText: String? = nil
    @State private var atBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.sm) {
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
                    } else {
                        TranscriptBlock(segments: segments, fontSize: fontSize)
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

/// Write text to a file the user picks, for the transcript exports.
func saveTextFile(_ content: String, fileName: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = fileName
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    if panel.runModal() == .OK, let url = panel.url {
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Copy text to the pasteboard, replacing what was there.
func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Transcript lines, shared shape with the overlay.
struct OverlayTranscriptList: View {
    @Environment(AppModel.self) private var model
    @AppStorage("reading.transcriptFontSize") private var transcriptFontSize = 14.0

    var body: some View {
        AutoScrollTranscript(segments: model.session.displaySegments, fontSize: transcriptFontSize)
    }
}

// MARK: Meetings

/// "Which meeting was this?" Pick the calendar event a saved meeting
/// belongs to, from the events of the meeting's own day. Choosing one
/// renames the meeting and brings the invited people and the event
/// details with it; "No calendar event" takes a wrong link away. Only
/// the saved meeting changes, the calendar is never edited.
struct MeetingEventPicker: View {
    let meeting: Meeting
    var onPick: (UpcomingEvent?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var events: [UpcomingEvent] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Which meeting was this?")
                .font(.headline)
            Text("Pick the calendar event this recording belongs to. The meeting takes its name, the invited people, and the event details.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !CalendarService.hasFullAccess {
                Text("Calendar access is off, so no events can be shown. Turn it on under Settings, Permissions.")
                    .font(.callout)
            } else if loaded && events.isEmpty {
                Text("No events on \(meeting.startedAt.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    Button {
                        onPick(nil)
                    } label: {
                        HStack {
                            Text("No calendar event")
                            Spacer()
                            if meeting.eventID.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(events) { event in
                        Button {
                            onPick(event)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(event.title)
                                    Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened)) · \(event.calendarName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if event.id == meeting.eventID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 340)
        .onAppear {
            let day = Calendar.current.startOfDay(for: meeting.startedAt)
            let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
            events = CalendarService.events(from: day, to: next)
            loaded = true
        }
    }
}

struct MeetingsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var search = ""
    @State private var tab = "Transcript"
    @State private var showEventPicker = false
    @State private var showSpeakerNames = false
    @State private var showConfirmSpeakers = false
    @State private var showImport = false
    @State private var droppedFiles: [URL] = []
    @State private var showCleaned = false
    @State private var cleaning = false
    @State private var cleanFailed = false
    @State private var cleanTask: Task<Void, Never>? = nil
    @State private var cleanProgress: (done: Int, total: Int)? = nil
    @State private var findingQuestions = false
    @State private var questionsFailed = false
    @State private var questionTask: Task<Void, Never>? = nil
    @State private var questionProgress: (done: Int, total: Int)? = nil
    @State private var writingScorecard = false
    @State private var scorecardFailed = false
    @State private var scorecardTask: Task<Void, Never>? = nil
    @State private var scorecardProgress: (done: Int, total: Int)? = nil
    @State private var findingThemes = false
    @State private var themesFailed = false
    @State private var themeTask: Task<Void, Never>? = nil
    @State private var themeProgress: (done: Int, total: Int)? = nil
    @State private var runningTransform = false
    @State private var transformFailed = false
    @State private var transformTask: Task<Void, Never>? = nil
    @State private var customTransformName = ""
    @State private var customTransformPrompt = ""
    @AppStorage("transforms.favoritesJSON") private var transformFavoritesJSON = ""
    @State private var regenerating = false
    @State private var seekRequest: Double? = nil
    @AppStorage("reading.transcriptFontSize") private var transcriptFontSize = 14.0
    @AppStorage("transcript.showTimestamps") private var showTimestamps = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped on the list's first appearance, so the list can
    /// settle in under it (see the List modifiers in the body).
    @State private var meetingsAppeared = false

    /// List rows are narrow: a composed title ("General · Nov 4, 2026
    /// at 9:19 PM") truncates before the time shows. Rows carry mode
    /// plus time of day; the date already sits on the line below, and
    /// the detail header keeps the full title.
    private func rowTitle(_ meeting: Meeting) -> String {
        let composedPrefix = "\(meeting.modeName) · "
        guard meeting.title.hasPrefix(composedPrefix) else { return meeting.title }
        return composedPrefix + meeting.startedAt.formatted(date: .omitted, time: .shortened)
    }

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
                    Text(rowTitle(meeting))
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
                    Button("Delete", role: .destructive) {
                        SessionAudioStore.delete(fileName: meeting.audioFileName)
                        context.delete(meeting)
                    }
                }
            }
            // Staggering, honestly scoped for a List: rows recycle
            // as they scroll, so a per-row appeared state would
            // replay and fight the recycling. Instead the whole
            // list fades in on its first appearance and settles on
            // the rubber-band spring — the rows land together, but
            // with the spring's overshoot settle, and the stagger
            // animation itself is spent on the detail tab swap
            // (see the detail VStack), where content does not
            // recycle.
            .opacity(meetingsAppeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? Motion.contentSwap(reduceMotion: true) : Motion.rubberBand, value: meetingsAppeared)
            .onAppear { meetingsAppeared = true }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import", systemImage: "square.and.arrow.down") {
                        showImport = true
                    }
                    .help("Import a transcript, an audio or video file, or a video link as a meeting")
                }
            }
            .sheet(isPresented: $showImport, onDismiss: { droppedFiles = [] }) {
                ImportMeetingSheet(initialFiles: droppedFiles)
            }
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
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter { $0.isFileURL }
            guard !files.isEmpty else { return false }
            droppedFiles = files
            showImport = true
            return true
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let meeting = meetings.first(where: { $0.id == model.selectedMeeting }) {
            // Meeting information saved with the meeting (1.6.0 on).
            // Older saves only kept the event id, so fall back to a
            // live lookup for those.
            let liveEvent = meeting.eventID.isEmpty ? nil : CalendarService.event(id: meeting.eventID)
            let attendeeList = meeting.attendees.isEmpty ? (liveEvent?.attendees ?? []) : meeting.attendees.components(separatedBy: ", ")
            let calendarLabel = meeting.calendarName.isEmpty ? (liveEvent?.calendarName ?? "") : meeting.calendarName
            let locationLabel = meeting.eventLocation.isEmpty ? (liveEvent?.location ?? "") : meeting.eventLocation
            let detailsText = meeting.eventDetails.isEmpty ? (liveEvent?.details ?? "") : meeting.eventDetails
            let whenStart = meeting.eventStart ?? liveEvent?.start
            let whenEnd = meeting.eventEnd ?? liveEvent?.end
            let shownSegments = (showCleaned && meeting.hasCleanedTranscript) ? meeting.cleanedSegments : meeting.segments
            let hasAudio = !meeting.audioFileName.isEmpty && SessionAudioStore.exists(fileName: meeting.audioFileName)
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(meeting.title).font(.title3.weight(.semibold))
                        Text("\(meeting.modeName) · \(Int(meeting.durationSeconds / 60)) min")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if !calendarLabel.isEmpty {
                            Label("Calendar: \(calendarLabel)", systemImage: "calendar.badge.checkmark")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if let whenStart, let whenEnd {
                            Label("\(whenStart.formatted(date: .abbreviated, time: .shortened)) – \(whenEnd.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if !attendeeList.isEmpty {
                            Label("Invited: \(attendeeList.joined(separator: ", "))", systemImage: "person.2")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !locationLabel.isEmpty {
                            Label(locationLabel, systemImage: "mappin.and.ellipse")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !detailsText.isEmpty {
                            Text(detailsText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        Button("Copy Summary") {
                            copyText(meeting.summary)
                        }
                        .disabled(meeting.summary.isEmpty)
                        Button("Copy Transcript") {
                            copyText(TranscriptSegment.plainText(shownSegments, includeTimestamps: showTimestamps))
                        }
                        .disabled(meeting.segments.isEmpty)
                        Button("Export…") {
                            saveTextFile(
                                TranscriptExport.markdown(title: meeting.title, date: meeting.startedAt, attendees: attendeeList, location: locationLabel, segments: shownSegments, summary: meeting.summary, includeTimestamps: showTimestamps),
                                fileName: TranscriptExport.fileName(title: meeting.title, date: meeting.startedAt)
                            )
                        }
                        .disabled(meeting.segments.isEmpty)
                        Button(meeting.eventID.isEmpty ? "Link to Calendar Event…" : "Change Calendar Event…") {
                            showEventPicker = true
                        }
                        Button("Name Speakers…") {
                            showSpeakerNames = true
                        }
                        .disabled(meeting.segments.isEmpty)
                    }
                }
                .sheet(isPresented: $showEventPicker) {
                    MeetingEventPicker(meeting: meeting) { event in
                        model.setCalendarEvent(event, for: meeting)
                        showEventPicker = false
                    }
                }
                .sheet(isPresented: $showSpeakerNames) {
                    SpeakerNamesSheet(meeting: meeting)
                }
                .sheet(isPresented: $showConfirmSpeakers) {
                    ConfirmSpeakersSheet(meeting: meeting,
                                         onPlaySample: hasAudio ? { offset in seekRequest = max(0, offset - 1) } : nil)
                }
                if hasAudio {
                    MeetingAudioPlayer(url: SessionAudioStore.url(fileName: meeting.audioFileName), seekRequest: $seekRequest)
                }
                if !meeting.suggestionList.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Suggestions from this session")
                            .font(.headline)
                        ForEach(Array(meeting.suggestionList.enumerated()), id: \.offset) { index, tip in
                            SuggestionRow(tip: tip)
                                .staggered(index: index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !meeting.segments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.sm) {
                            ForEach(SpeakerNames.distinctNames(segments: meeting.segments), id: \.self) { name in
                                Button {
                                    showSpeakerNames = true
                                } label: {
                                    Label(name, systemImage: "person.fill")
                                        .font(.caption.weight(.medium))
                                }
                                .buttonStyle(ChipButtonStyle(selected: false))
                                .help("Name the speakers")
                            }
                        }
                    }
                    if !meeting.diarizationNote.isEmpty {
                        Label(meeting.diarizationNote, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !meeting.speakersConfirmed,
                   SpeakerConfirmation.needsConfirmation(segments: meeting.segments) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Who was in this meeting?")
                            .font(.headline)
                        Text("The voices on the other side are not confirmed yet. Voices are separated by sound, so one person can appear as two speakers, and some lines get no name at all.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: Space.sm) {
                            Button("Confirm Speakers…") { showConfirmSpeakers = true }
                                .buttonStyle(InkButtonStyle())
                            Button("Looks Right") {
                                meeting.speakersConfirmed = true
                                try? meeting.modelContext?.save()
                            }
                            .buttonStyle(QuietButtonStyle())
                            Spacer()
                        }
                    }
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Surface.panel, in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Surface.hairline, lineWidth: 1))
                }
                Picker("View", selection: $tab) {
                    Text("Transcript").tag("Transcript")
                    Text("Notes").tag("Notes")
                    Text("Summary").tag("Summary")
                    Text("Questions").tag("Questions")
                    Text("Scorecard").tag("Scorecard")
                    Text("Create").tag("Create")
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
                            HStack(spacing: Space.sm) {
                                Button {
                                    regenerating = true
                                    MeetingImporter.summarize(meeting: meeting) { regenerating = false }
                                } label: {
                                    Label(regenerating ? "Writing…" : "Regenerate Summary", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(QuietButtonStyle())
                                .disabled(regenerating || meeting.segments.isEmpty)
                                if regenerating { ProgressView().controlSize(.small) }
                                Spacer()
                            }
                            if meeting.summary.isEmpty {
                                Text("No summary yet. It is written when the call stops, if a model is reachable.")
                            } else {
                                DocTextView(text: meeting.summary)
                            }
                            if !meeting.followUp.isEmpty {
                                Text("Follow-Up Draft").font(.headline)
                                DocTextView(text: meeting.followUp)
                            }
                            themesSection(meeting: meeting, hasAudio: hasAudio)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case "Questions":
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(spacing: Space.sm) {
                            Button {
                                findingQuestions = true
                                questionsFailed = false
                                questionProgress = nil
                                questionTask = QuestionFinder.find(meeting: meeting, onProgress: { done, total in
                                    questionProgress = (done, total)
                                }) { success in
                                    findingQuestions = false
                                    questionProgress = nil
                                    questionTask = nil
                                    questionsFailed = !success
                                }
                            } label: {
                                Label(findingQuestions ? (questionProgress.map { "Finding… \($0.done) of \($0.total)" } ?? "Finding…") : (meeting.questionsExtracted ? "Find Questions Again" : "Find Questions"), systemImage: "questionmark.bubble")
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(findingQuestions || meeting.segments.isEmpty)
                            if findingQuestions {
                                ProgressView().controlSize(.small)
                                Button("Cancel") {
                                    questionTask?.cancel()
                                    questionTask = nil
                                    findingQuestions = false
                                    questionProgress = nil
                                }
                                .buttonStyle(QuietButtonStyle())
                            }
                            Spacer()
                        }
                        if questionsFailed {
                            Text("Finding the questions did not finish. The transcript is unchanged.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if meeting.questionPairs.isEmpty {
                            Text(meeting.questionsExtracted
                                 ? "No questions to you were found in this transcript."
                                 : "The questions the other side asked, with the answers you gave, pulled out of the transcript and kept apart from it. Finding them runs on this Mac and can take a few minutes on a long call.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: Space.md) {
                                    ForEach(Array(meeting.questionPairs.enumerated()), id: \.offset) { index, pair in
                                        if index > 0 { Divider() }
                                        HStack(alignment: .top, spacing: Space.sm) {
                                            if hasAudio {
                                                Button {
                                                    seekRequest = max(0, pair.atSeconds - 2)
                                                } label: {
                                                    Text(TranscriptTime.label(seconds: pair.atSeconds))
                                                        .font(.caption.monospacedDigit())
                                                        .frame(width: 48, alignment: .trailing)
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundStyle(.secondary)
                                                .help("Play from just before this question")
                                            } else {
                                                Text(TranscriptTime.label(seconds: pair.atSeconds))
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 48, alignment: .trailing)
                                            }
                                            VStack(alignment: .leading, spacing: Space.xs) {
                                                Text(pair.asker)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                Text(pair.question)
                                                    .font(.body.weight(.semibold))
                                                    .textSelection(.enabled)
                                                if pair.answer.isEmpty {
                                                    Text("No answer in the transcript.")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                } else {
                                                    Text(pair.answer)
                                                        .foregroundStyle(.secondary)
                                                        .textSelection(.enabled)
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                case "Scorecard":
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(spacing: Space.sm) {
                            Button {
                                writingScorecard = true
                                scorecardFailed = false
                                scorecardProgress = nil
                                scorecardTask = ScorecardWriter.write(meeting: meeting, onProgress: { done, total in
                                    scorecardProgress = (done, total)
                                }) { success in
                                    writingScorecard = false
                                    scorecardProgress = nil
                                    scorecardTask = nil
                                    scorecardFailed = !success
                                }
                            } label: {
                                Label(writingScorecard ? (scorecardProgress.map { "Writing… \($0.done) of \($0.total)" } ?? "Writing…") : (meeting.scorecardWritten ? "Write Scorecard Again" : "Write Scorecard"), systemImage: "list.clipboard")
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(writingScorecard || meeting.segments.isEmpty)
                            if writingScorecard {
                                ProgressView().controlSize(.small)
                                Button("Cancel") {
                                    scorecardTask?.cancel()
                                    scorecardTask = nil
                                    writingScorecard = false
                                    scorecardProgress = nil
                                }
                                .buttonStyle(QuietButtonStyle())
                            }
                            Spacer()
                        }
                        if scorecardFailed {
                            Text("Writing the scorecard did not finish. The transcript is unchanged.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let card = meeting.scorecard, !card.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: Space.lg) {
                                    if !card.verdict.isEmpty {
                                        VStack(alignment: .leading, spacing: Space.xs) {
                                            Text("The likely read")
                                                .font(.headline)
                                            Text(card.verdict)
                                                .textSelection(.enabled)
                                        }
                                        .padding(Space.md)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Surface.panel, in: RoundedRectangle(cornerRadius: Radius.card))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Surface.hairline, lineWidth: 1))
                                    }
                                    scorecardSection("What they probed", points: card.probed, hasAudio: hasAudio)
                                    scorecardSection("Evidence you gave", points: card.evidence, hasAudio: hasAudio)
                                    scorecardSection("Where you were thin", points: card.gaps, hasAudio: hasAudio)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Text(meeting.scorecardWritten
                                 ? "No scorecard could be written from this transcript."
                                 : "The scorecard the other side would file on you after this call: what they probed, the evidence you gave, and where you were thin. Writing it runs on this Mac and can take a few minutes on a long call.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                case "Create":
                    createTab(meeting: meeting)
                default:
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(spacing: Space.sm) {
                            Button {
                                showTimestamps.toggle()
                            } label: {
                                Label(showTimestamps ? "Hide Timestamps" : "Show Timestamps", systemImage: "clock")
                            }
                            .buttonStyle(QuietButtonStyle())
                            .help("Show when each line was said, counted from the start of the session. When the session audio is saved, tap a line to hear that moment.")
                            Spacer()
                            if meeting.hasCleanedTranscript {
                                Picker("Transcript version", selection: $showCleaned) {
                                    Text("Original").tag(false)
                                    Text("Cleaned").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 200)
                            }
                            Button {
                                cleaning = true
                                cleanFailed = false
                                cleanProgress = nil
                                cleanTask = TranscriptCleaner.clean(meeting: meeting, onProgress: { done, total in
                                    cleanProgress = (done, total)
                                }) { success in
                                    cleaning = false
                                    cleanProgress = nil
                                    cleanTask = nil
                                    cleanFailed = !success
                                    if success { showCleaned = true }
                                }
                            } label: {
                                Label(cleaning ? (cleanProgress.map { "Cleaning… \($0.done) of \($0.total)" } ?? "Cleaning…") : "Clean Transcript", systemImage: "sparkles")
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(cleaning || meeting.segments.isEmpty)
                            if cleaning {
                                ProgressView().controlSize(.small)
                                Button("Cancel") {
                                    cleanTask?.cancel()
                                    cleanTask = nil
                                    cleaning = false
                                    cleanProgress = nil
                                }
                                .buttonStyle(QuietButtonStyle())
                            }
                        }
                        if showCleaned && meeting.hasCleanedTranscript {
                            Label("Viewing cleaned transcript. The original is kept and never overwritten.", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if cleanFailed {
                            Text("The cleanup did not finish. The original transcript is unchanged.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if showTimestamps {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: Space.sm) {
                                    ForEach(shownSegments.filter(\.isFinal)) { segment in
                                        HStack(alignment: .top, spacing: Space.sm) {
                                            if hasAudio, let start = segment.startOffset {
                                                Button {
                                                    seekRequest = max(0, start - 2)
                                                } label: {
                                                    Text(TranscriptTime.label(seconds: start))
                                                        .font(.caption.monospacedDigit())
                                                        .frame(width: 48, alignment: .trailing)
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundStyle(.secondary)
                                                .help("Play from just before this line")
                                            } else {
                                                Text(segment.startOffset.map { TranscriptTime.label(seconds: $0) } ?? "")
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 48, alignment: .trailing)
                                            }
                                            TranscriptRow(segment: segment)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ScrollView {
                                TranscriptBlock(segments: shownSegments, fontSize: transcriptFontSize)
                            }
                        }
                    }
                }
            }
            .padding(Space.margin)
            // The detail tab swap, animated with the stagger
            // animation (index 0, so no delay — the timing and
            // curve are what carry over): switching Transcript /
            // Notes / Summary / Questions / Create cross-settles
            // instead of cutting hard.
            .animation(Motion.stagger(index: 0, reduceMotion: reduceMotion), value: tab)
            .onChange(of: meeting.id) { _, _ in
                showCleaned = false
                cleanFailed = false
                questionsFailed = false
                transformFailed = false
            }
        } else {
            ContentUnavailableView("No Meeting Selected", systemImage: "sidebar.right")
        }
    }

    // MARK: Create tab

    /// The saved transform favorites, shared across meetings.
    private var transformFavorites: [TransformFavorite] {
        TransformFavorite.decode(transformFavoritesJSON)
    }

    /// One scorecard section: a heading and its points, each with
    /// the moment it rests on, tappable to hear that moment when
    /// the session audio is saved, like the Questions rows.
    @ViewBuilder
    private func scorecardSection(_ title: String, points: [ScorecardPoint], hasAudio: Bool) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title).font(.headline)
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: Space.sm) {
                        if hasAudio {
                            Button {
                                seekRequest = max(0, point.atSeconds - 2)
                            } label: {
                                Text(TranscriptTime.label(seconds: point.atSeconds))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 48, alignment: .trailing)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Play from just before this moment")
                        } else {
                            Text(TranscriptTime.label(seconds: point.atSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                        Text(point.text)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// The call's themes, shown under the summary: the topics the
    /// call worked on, each with one line on what was said and the
    /// moments it came up, tappable to the audio when the meeting
    /// has any. Found on demand by Find Themes, the same Deep
    /// pattern as Questions and the scorecard; the summary itself
    /// is never touched.
    @ViewBuilder
    private func themesSection(meeting: Meeting, hasAudio: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text("Themes").font(.headline)
                Spacer()
                Button {
                    findingThemes = true
                    themesFailed = false
                    themeProgress = nil
                    themeTask = ThemeFinder.find(meeting: meeting, onProgress: { done, total in
                        themeProgress = (done, total)
                    }) { success in
                        findingThemes = false
                        themeProgress = nil
                        themeTask = nil
                        themesFailed = !success
                    }
                } label: {
                    Label(findingThemes ? (themeProgress.map { "Finding… \($0.done) of \($0.total)" } ?? "Finding…") : (meeting.themesExtracted ? "Find Themes Again" : "Find Themes"), systemImage: "tag")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(findingThemes || meeting.segments.isEmpty)
                if findingThemes {
                    ProgressView().controlSize(.small)
                    Button("Cancel") {
                        themeTask?.cancel()
                        themeTask = nil
                        findingThemes = false
                        themeProgress = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            if themesFailed {
                Text("Finding the themes did not finish. The transcript is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if meeting.themes.isEmpty {
                Text(meeting.themesExtracted
                     ? "No themes stood out in this transcript."
                     : "The topics this call worked on, each pinned to the moments it came up, so you can jump from a topic to the moment instead of scanning the notes. Finding them runs on this Mac and can take a few minutes on a long call.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(meeting.themes.enumerated()), id: \.offset) { _, theme in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(theme.title).font(.callout.weight(.semibold))
                        Text(theme.detail)
                            .textSelection(.enabled)
                        HStack(spacing: Space.sm) {
                            ForEach(theme.atSeconds, id: \.self) { moment in
                                if hasAudio {
                                    Button {
                                        seekRequest = max(0, moment - 2)
                                    } label: {
                                        Text(TranscriptTime.label(seconds: moment))
                                            .font(.caption.monospacedDigit())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help("Play from just before this moment")
                                } else {
                                    Text(TranscriptTime.label(seconds: moment))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Turn this meeting into something else: a brief summary, a
    /// thank-you email, study questions, a translation, or the
    /// user's own prompt. Everything runs on this Mac through the
    /// Deep model, and every result is saved on the meeting.
    @ViewBuilder
    private func createTab(meeting: Meeting) -> some View {
        let picked = TransformSourcePicker.pick(cleaned: meeting.cleanedSegments, original: meeting.segments)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    if let picked {
                        Text("Reading: \(picked.source.label). Transforms run on this Mac, and the results stay on this meeting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This meeting has no transcript yet, so there is nothing to work from.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Space.sm) {
                        ForEach(BuiltInTransforms.all, id: \.id) { definition in
                            Button {
                                startTranscriptTransform(meeting: meeting, definition: definition)
                            } label: {
                                Text(definition.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(runningTransform || picked == nil)
                        }
                    }
                    HStack(spacing: Space.sm) {
                        Menu {
                            ForEach(TranslationPrompts.languages, id: \.self) { language in
                                Button(language) {
                                    startSummaryTransform(meeting: meeting, definition: BuiltInTransforms.translate(language: language))
                                }
                            }
                        } label: {
                            Label("Translate Summary", systemImage: "character.bubble")
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(runningTransform || meeting.summary.isEmpty)
                        Menu {
                            ForEach(BuiltInTransforms.tones, id: \.self) { tone in
                                Button(tone) {
                                    startSummaryTransform(meeting: meeting, definition: BuiltInTransforms.toneRewrite(tone: tone))
                                }
                            }
                        } label: {
                            Label("Rewrite Summary", systemImage: "textformat")
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(runningTransform || meeting.summary.isEmpty)
                        Spacer()
                    }
                    if meeting.summary.isEmpty {
                        Text("Translate and Rewrite work on the summary. This meeting has no summary yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if runningTransform {
                        HStack(spacing: Space.sm) {
                            ProgressView().controlSize(.small)
                            Text("Writing…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Cancel") {
                                transformTask?.cancel()
                                transformTask = nil
                                runningTransform = false
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                    }
                    if transformFailed {
                        Text("That did not finish. Nothing was saved.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Your Own Prompt")
                        .font(.headline)
                    TextField("Name (optional)", text: $customTransformName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(runningTransform)
                    TextField("What should it do? For example: Turn this into a short post I can share.", text: $customTransformPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                        .disabled(runningTransform)
                    HStack(spacing: Space.sm) {
                        Button("Run") {
                            runCustomTransform(meeting: meeting)
                        }
                        .buttonStyle(InkButtonStyle())
                        .disabled(runningTransform || picked == nil || customTransformPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Save as Favorite") {
                            saveCustomFavorite()
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(customTransformPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    Text("A custom prompt reads the same transcript as the transforms above. Save one as a favorite and it is offered on every meeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !transformFavorites.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Favorites")
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Space.sm) {
                            ForEach(transformFavorites) { favorite in
                                Button {
                                    startTranscriptTransform(meeting: meeting, definition: TransformDefinition(id: "favorite-\(favorite.id)", name: favorite.name, instruction: favorite.prompt))
                                } label: {
                                    Text(favorite.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(QuietButtonStyle())
                                .disabled(runningTransform || picked == nil)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        deleteTransformFavorite(favorite)
                                    }
                                }
                            }
                        }
                        Text("Right-click a favorite to delete it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: Space.md) {
                    if meeting.transformResults.isEmpty {
                        Text("Nothing made yet. Pick a transform above and the result will be saved here, on this meeting, next to the summary.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(meeting.transformResults.reversed()) { result in
                            VStack(alignment: .leading, spacing: Space.sm) {
                                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                                    Text(result.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(result.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Source: \(result.source.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                DocTextView(text: result.text)
                                HStack(spacing: Space.sm) {
                                    Button("Copy") {
                                        copyText(result.text)
                                    }
                                    .buttonStyle(QuietButtonStyle())
                                    Button("Export…") {
                                        saveTextFile(
                                            transformMarkdown(meeting: meeting, result: result),
                                            fileName: TranscriptExport.fileName(title: "\(meeting.title) \(result.name)", date: result.createdAt)
                                        )
                                    }
                                    .buttonStyle(QuietButtonStyle())
                                    Spacer()
                                }
                            }
                            .padding(Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Surface.panel, in: RoundedRectangle(cornerRadius: Radius.card))
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Surface.hairline, lineWidth: 1))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Start a transform, the Create tab's one running state: one
    /// job at a time, and a failure shows its line and saves nothing.
    private func startTransform(meeting: Meeting, definition: TransformDefinition, inputText: String, inputLabel: String, source: TransformSource) {
        transformFailed = false
        runningTransform = true
        transformTask = MeetingTransforms.run(meeting: meeting, definition: definition, inputText: inputText, inputLabel: inputLabel, source: source) { success in
            runningTransform = false
            transformTask = nil
            transformFailed = !success
        }
    }

    /// A transform that reads the meeting's transcript: the Clean
    /// Transcript when there is one, the original otherwise.
    private func startTranscriptTransform(meeting: Meeting, definition: TransformDefinition) {
        guard let picked = TransformSourcePicker.pick(cleaned: meeting.cleanedSegments, original: meeting.segments) else { return }
        startTransform(meeting: meeting, definition: definition, inputText: TranscriptSegment.plainText(picked.segments), inputLabel: picked.source.label, source: picked.source)
    }

    /// A transform that reads the meeting's summary: Translate and
    /// the tone rewrites. The result is stamped with the original
    /// source, because TransformSource names transcripts only; the
    /// prompt itself is told the text is the summary.
    private func startSummaryTransform(meeting: Meeting, definition: TransformDefinition) {
        guard !meeting.summary.isEmpty else { return }
        startTransform(meeting: meeting, definition: definition, inputText: meeting.summary, inputLabel: "Summary", source: .summary)
    }

    private func runCustomTransform(meeting: Meeting) {
        let prompt = customTransformPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let name = customTransformName.trimmingCharacters(in: .whitespacesAndNewlines)
        startTranscriptTransform(meeting: meeting, definition: TransformDefinition(id: "custom", name: name.isEmpty ? "Custom" : name, instruction: prompt))
    }

    private func saveCustomFavorite() {
        let prompt = customTransformPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let name = customTransformName.trimmingCharacters(in: .whitespacesAndNewlines)
        var favorites = transformFavorites
        favorites.append(TransformFavorite(name: name.isEmpty ? "Custom Prompt" : name, prompt: prompt))
        transformFavoritesJSON = TransformFavorite.encode(favorites)
    }

    private func deleteTransformFavorite(_ favorite: TransformFavorite) {
        transformFavoritesJSON = TransformFavorite.encode(transformFavorites.filter { $0.id != favorite.id })
    }

    /// One saved result as a Markdown file the user keeps.
    private func transformMarkdown(meeting: Meeting, result: TransformResult) -> String {
        "# \(result.name)\n\nMeeting: \(meeting.title)\nMade: \(result.createdAt.formatted(date: .complete, time: .shortened))\nWritten from: \(result.source.label)\n\n\(result.text)\n"
    }
}

/// Rename the speakers of a saved meeting. The transcript shows
/// labels ("Them", "Speaker 1", or a name); this sheet rewrites one
/// label into a real name across every line at once, so the meeting
/// view, the export, and anything generated from the transcript all
/// follow. The invited people are offered as one-tap picks.
struct SpeakerNamesSheet: View {
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]

    private var speakers: [String] {
        SpeakerNames.distinctNames(segments: meeting.segments)
    }

    private var invited: [String] {
        let attendeeList = meeting.attendees.isEmpty ? [] : meeting.attendees.components(separatedBy: ", ")
        return SpeakerNames.invitationCandidates(
            attendees: attendeeList, title: meeting.title, details: meeting.eventDetails,
            myName: UserDefaults.standard.string(forKey: "speaker.myName") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Name the Speakers")
                .font(.title3.weight(.semibold))
            Text("These are the names the transcript shows now. Change one and every line from that speaker follows, in this view, in the export, and in the text the summary is written from. Only name someone you know was speaking.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("An existing summary or follow-up keeps the names it was written with. Regenerate the summary from the Summary tab to refresh it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(speakers, id: \.self) { speaker in
                    HStack(spacing: Space.sm) {
                        Text(speaker)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .frame(width: 112, alignment: .leading)
                        TextField(speaker, text: binding(for: speaker))
                            .textFieldStyle(.roundedBorder)
                        if !invited.isEmpty {
                            Menu {
                                ForEach(invited, id: \.self) { person in
                                    Button(person) { names[speaker] = person }
                                }
                            } label: {
                                Image(systemName: "person.crop.rectangle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .help("Pick from the invited people")
                        }
                    }
                }
            }
            HStack(spacing: Space.sm) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Names") {
                    var mapping: [String: String] = [:]
                    for speaker in speakers {
                        let typed = (names[speaker] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !typed.isEmpty, typed != speaker { mapping[speaker] = typed }
                    }
                    if !mapping.isEmpty {
                        let updated = SpeakerNames.applying(segments: meeting.segments, mapping: mapping)
                        meeting.transcriptJSON = TranscriptSegment.encode(updated)
                        try? meeting.modelContext?.save()
                    }
                    dismiss()
                }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
        .background(Surface.canvas)
        .onAppear {
            for speaker in speakers where names[speaker] == nil {
                names[speaker] = speaker
            }
        }
    }

    private func binding(for speaker: String) -> Binding<String> {
        Binding(
            get: { names[speaker] ?? speaker },
            set: { names[speaker] = $0 }
        )
    }
}

/// Confirm who was actually in a meeting. Diarization groups the
/// other side by voice, and one person can land in two groups;
/// this sheet lists each voice with its line count, a sample line,
/// and a listen button when the audio is saved, and applies the
/// answer as one rename pass: two voices given the same name
/// merge, and the one-person answer names every voice at once,
/// the unnamed lines included. Confirming is remembered on the
/// meeting, so it is asked once.
struct ConfirmSpeakersSheet: View {
    let meeting: Meeting
    /// Seeks the meeting's audio player to a voice's first line.
    /// Nil when the meeting has no saved audio.
    var onPlaySample: ((Double) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]
    @State private var unassignedName = ""
    @State private var justOnePerson = false
    @State private var oneName = ""
    @State private var applied = false
    @State private var regenerating = false

    private var voices: [SpeakerConfirmation.Voice] {
        SpeakerConfirmation.voices(in: meeting.segments)
    }

    private var unassigned: SpeakerConfirmation.Unassigned? {
        SpeakerConfirmation.unassigned(in: meeting.segments)
    }

    private var invited: [String] {
        let attendeeList = meeting.attendees.isEmpty ? [] : meeting.attendees.components(separatedBy: ", ")
        return SpeakerNames.invitationCandidates(
            attendees: attendeeList, title: meeting.title, details: meeting.eventDetails,
            myName: UserDefaults.standard.string(forKey: "speaker.myName") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if applied {
                Text("Speakers confirmed.")
                    .font(.title3.weight(.semibold))
                if !meeting.summary.isEmpty {
                    Text("The summary and follow-up still use the names they were written with.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Space.sm) {
                        Button {
                            regenerating = true
                            MeetingImporter.summarize(meeting: meeting) { regenerating = false }
                        } label: {
                            Label(regenerating ? "Writing…" : "Regenerate Summary", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(regenerating)
                        if regenerating { ProgressView().controlSize(.small) }
                        Spacer()
                    }
                }
                HStack(spacing: Space.sm) {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(InkButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Confirm the Speakers")
                    .font(.title3.weight(.semibold))
                Text(voices.isEmpty
                     ? "The voice check found no distinct voices on the other side. The lines below have no voice yet; name them here, or use the one-person answer."
                     : voices.count == 1
                        ? "The voice check found 1 potential speaker on the other side, with a line from them. Give them their name."
                        : "The voice check found \(voices.count) potential speakers on the other side, with a line from each. If one person appears twice, give both voices the same name and they merge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("It was just one person", isOn: $justOnePerson)
                    .toggleStyle(.checkbox)
                if justOnePerson {
                    HStack(spacing: Space.sm) {
                        Text("Their name")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .frame(width: 112, alignment: .leading)
                        TextField("Name", text: $oneName)
                            .textFieldStyle(.roundedBorder)
                        if !invited.isEmpty {
                            Menu {
                                ForEach(invited, id: \.self) { person in
                                    Button(person) { oneName = person }
                                }
                            } label: {
                                Image(systemName: "person.crop.rectangle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .help("Pick from the invited people")
                        }
                    }
                    Text("Every line on the other side gets this name, including the lines that have none.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: Space.md) {
                        ForEach(voices, id: \.name) { voice in
                            VStack(alignment: .leading, spacing: Space.xs) {
                                HStack(spacing: Space.sm) {
                                    Text(voice.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                        .frame(width: 112, alignment: .leading)
                                    TextField(voice.name, text: binding(for: voice))
                                        .textFieldStyle(.roundedBorder)
                                    if let onPlaySample, let offset = voice.firstOffset {
                                        Button {
                                            onPlaySample(offset)
                                        } label: {
                                            Image(systemName: "play.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .help("Hear this voice")
                                    }
                                    if !invited.isEmpty {
                                        Menu {
                                            ForEach(invited, id: \.self) { person in
                                                Button(person) { names[voice.name] = person }
                                            }
                                        } label: {
                                            Image(systemName: "person.crop.rectangle")
                                        }
                                        .menuStyle(.borderlessButton)
                                        .menuIndicator(.hidden)
                                        .help("Pick from the invited people")
                                    }
                                }
                                Text("\(voice.lineCount) lines · \(voice.sample)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .padding(.leading, 120)
                            }
                        }
                        if let unassigned {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("Some lines have no voice. They are not another speaker; name them here, or use the one-person answer above.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: Space.sm) {
                                    Text("No voice found")
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                        .frame(width: 112, alignment: .leading)
                                    TextField("Name for these lines", text: $unassignedName)
                                        .textFieldStyle(.roundedBorder)
                                    if let onPlaySample, let offset = unassigned.firstOffset {
                                        Button {
                                            onPlaySample(offset)
                                        } label: {
                                            Image(systemName: "play.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .help("Hear these lines")
                                    }
                                    if !invited.isEmpty {
                                        Menu {
                                            ForEach(invited, id: \.self) { person in
                                                Button(person) { unassignedName = person }
                                            }
                                        } label: {
                                            Image(systemName: "person.crop.rectangle")
                                        }
                                        .menuStyle(.borderlessButton)
                                        .menuIndicator(.hidden)
                                        .help("Pick from the invited people")
                                    }
                                }
                                Text("\(unassigned.lineCount) lines · \(unassigned.sample)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .padding(.leading, 120)
                            }
                        }
                    }
                }
                HStack(spacing: Space.sm) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Apply Names") { apply() }
                        .buttonStyle(InkButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(justOnePerson && oneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
        .background(Surface.canvas)
        .onAppear(perform: prefill)
    }

    private func prefill() {
        for voice in voices where names[voice.name] == nil {
            names[voice.name] = SpeakerConfirmation.isGeneric(voice.name) ? "" : voice.name
        }
        if oneName.isEmpty {
            oneName = voices.first(where: { !SpeakerConfirmation.isGeneric($0.name) })?.name
                ?? invited.first ?? ""
        }
    }

    private func apply() {
        var mapping: [String: String] = [:]
        if justOnePerson {
            let name = oneName.trimmingCharacters(in: .whitespacesAndNewlines)
            for voice in voices where voice.name != name { mapping[voice.name] = name }
            if unassigned != nil { mapping["Them"] = name }
        } else {
            for voice in voices {
                let typed = (names[voice.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !typed.isEmpty, typed != voice.name { mapping[voice.name] = typed }
            }
            let loose = unassignedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if unassigned != nil, !loose.isEmpty { mapping["Them"] = loose }
        }
        if !mapping.isEmpty {
            let updated = SpeakerNames.applying(segments: meeting.segments, mapping: mapping)
            meeting.transcriptJSON = TranscriptSegment.encode(updated)
        }
        meeting.speakersConfirmed = true
        try? meeting.modelContext?.save()
        applied = true
    }

    private func binding(for voice: SpeakerConfirmation.Voice) -> Binding<String> {
        Binding(
            get: { names[voice.name] ?? "" },
            set: { names[voice.name] = $0 }
        )
    }
}

/// Plays a meeting's saved session audio, recorded with the other
/// side on the left and you on the right, and offers the file itself
/// in Finder for anything the player cannot do.
struct MeetingAudioPlayer: View {
    let url: URL
    /// A moment another view asks the player to jump to, in seconds:
    /// tapping a transcript timestamp sets it, the player seeks,
    /// plays, and clears it.
    var seekRequest: Binding<Double?> = .constant(nil)
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var progress = 0.0
    @State private var duration = 0.0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: Space.sm) {
            Label("Session Audio", systemImage: "waveform")
                .font(.callout.weight(.medium))
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")
            Slider(value: $progress, in: 0...max(duration, 1)) { editing in
                isScrubbing = editing
                if !editing { seek(to: progress) }
            }
            Text("\(clock(progress)) / \(clock(duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(QuietButtonStyle())
        }
        .onAppear(perform: setUp)
        .onDisappear(perform: tearDown)
        // The detail view stays alive while the selection moves
        // between meetings, so the player must follow the file it
        // was given: without this, the first meeting's audio kept
        // playing for every meeting opened after it.
        .onChange(of: url) { _, _ in
            tearDown()
            setUp()
        }
        .onChange(of: seekRequest.wrappedValue) { _, newValue in
            if let newValue {
                seek(to: newValue)
                player?.play()
                isPlaying = true
                seekRequest.wrappedValue = nil
            }
        }
    }

    private func setUp() {
        progress = 0
        duration = 0
        isPlaying = false
        let player = AVPlayer(url: url)
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak player] time in
            // The observer fires on the main queue, so the view's
            // state is safe to touch inside assumeIsolated.
            MainActor.assumeIsolated {
                if !isScrubbing {
                    progress = time.seconds.isFinite ? time.seconds : 0
                }
                if let itemDuration = player?.currentItem?.duration.seconds, itemDuration.isFinite {
                    duration = itemDuration
                }
                isPlaying = player?.timeControlStatus == .playing
            }
        }
    }

    private func tearDown() {
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player = nil
        isPlaying = false
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, progress >= duration - 0.3 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        progress = seconds
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: Modes

/// The Modes library, shaped after Metaview's template library
/// (studied 2026-11-12 at Nils's request): grouped list with
/// search on the left, a detail that follows the SELECTION on the
/// right. Selecting never changes the live mode; "Use" does, the
/// way Metaview separates browsing a template from setting it as
/// the default. Built-ins are read-only and carry a Customize
/// action that copies them into an editable mode of your own.
struct ModesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var selectedID: String?
    @State private var searchText = ""

    private var effectiveSelection: String { selectedID ?? model.activeModeID }

    var body: some View {
        HSplitView {
            modeList
                .frame(minWidth: 240)
            modeDetail
                .frame(minWidth: 340)
        }
        .navigationTitle("Modes")
    }

    // MARK: List

    private var modeList: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Button("New Mode", systemImage: "plus") { createMode() }
                .buttonStyle(InkButtonStyle())
            TextField("Search modes", text: $searchText)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
                    groupLabel("Built-in")
                    ForEach(filteredBuiltIns) { mode in
                        modeRow(id: mode.id, name: mode.name, subtitle: firstLine(of: mode.prompt))
                    }
                    groupLabel("Your Modes")
                    let customs = filteredCustoms
                    if customs.isEmpty {
                        Text(searchText.isEmpty
                             ? "No modes of your own yet. Customize a built-in to start."
                             : "No mode matches your search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Space.sm)
                    }
                    ForEach(customs, id: \.uuid) { custom in
                        modeRow(id: custom.idString, name: custom.name, subtitle: firstLine(of: custom.promptText))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Space.md)
    }

    private var filteredBuiltIns: [ModeDefinition] {
        guard !searchText.isEmpty else { return BuiltInModes.all }
        return BuiltInModes.all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredCustoms: [CustomMode] {
        guard !searchText.isEmpty else { return model.customModes() }
        return model.customModes().filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.top, Space.xs)
            .padding(.horizontal, Space.sm)
    }

    private func modeRow(id: String, name: String, subtitle: String) -> some View {
        Button {
            selectedID = id
        } label: {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if model.activeModeID == id {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(Palette.accent.opacity(0.14), in: Capsule())
                }
            }
            .padding(.vertical, Space.xs)
            .padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(effectiveSelection == id ? Surface.inset : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    @ViewBuilder
    private var modeDetail: some View {
        let id = effectiveSelection
        if let custom = model.customModes().first(where: { $0.idString == id }) {
            customDetail(custom)
        } else {
            builtInDetail(BuiltInModes.mode(id: id))
        }
    }

    private func detailHeader<Actions: View>(name: String, isActive: Bool, id: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: Space.sm) {
            Text(name).font(.title3.weight(.semibold)).lineLimit(1)
            Spacer()
            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.accentText)
            } else {
                Button("Use") {
                    model.activeModeID = id
                    selectedID = id
                }
                .buttonStyle(InkButtonStyle(compact: true))
            }
            actions()
        }
    }

    private func builtInDetail(_ mode: ModeDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                detailHeader(name: mode.name, isActive: model.activeModeID == mode.id, id: mode.id) {
                    Button("Customize") { customize(mode) }
                        .buttonStyle(QuietButtonStyle())
                        .help("Copy this built-in into your own editable mode")
                }
                Text(firstSentence(of: mode.prompt))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                sectionLabel("Prompt")
                Text(mode.prompt)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.sm)
                    .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Text("Built-in prompts are fixed. Customize this mode to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                sectionLabel("Note Sections")
                sectionList(ModeSections.titles(from: mode.notesTemplate))
                contextEditor(forModeID: mode.id)
            }
            .padding(Space.margin)
        }
    }

    private func customDetail(_ custom: CustomMode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                // The name field IS the header (Metaview's shape):
                // no second title printed underneath it.
                HStack(spacing: Space.sm) {
                    TextField("Mode name", text: Binding(get: { custom.name }, set: { custom.name = $0; try? context.save() }))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if model.activeModeID == custom.idString {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                    } else {
                        Button("Use") {
                            model.activeModeID = custom.idString
                            selectedID = custom.idString
                        }
                        .buttonStyle(InkButtonStyle(compact: true))
                    }
                    Button("Duplicate") { duplicate(custom) }
                        .buttonStyle(QuietButtonStyle())
                    Button("Delete", role: .destructive) { delete(custom) }
                        .buttonStyle(QuietButtonStyle())
                }
                sectionLabel("Prompt")
                TextEditor(text: Binding(get: { custom.promptText }, set: { custom.promptText = $0; try? context.save() }))
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(Space.xs)
                    .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                sectionLabel("Note Sections")
                TextEditor(text: Binding(get: { custom.notesTemplate }, set: { custom.notesTemplate = $0; try? context.save() }))
                    .font(.body)
                    .frame(minHeight: 80)
                    .padding(Space.xs)
                    .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Text("One section per line. A new meeting in this mode starts its notes with these sections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                contextEditor(forModeID: custom.idString)
            }
            .padding(Space.margin)
        }
    }

    private func contextEditor(forModeID id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            sectionLabel("Custom Context for This Mode")
            TextEditor(text: Binding(
                get: {
                    if let custom = model.customModes().first(where: { $0.idString == id }) {
                        return custom.customContext
                    }
                    return UserDefaults.standard.string(forKey: "mode.context.\(id)") ?? ""
                },
                set: { model.setModeContext($0, forModeID: id) }
            ))
            .font(.body)
            .frame(minHeight: 80)
            Text("Salary bands, crib notes, names, anything the answers should know in this mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }

    private func sectionList(_ titles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if titles.isEmpty {
                Text("No sections. This mode starts notes blank.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Space.xs)
            }
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                HStack(spacing: Space.sm) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, alignment: .trailing)
                    Text(title).font(.callout)
                    Spacer()
                }
                .padding(.vertical, Space.xs)
                if index < titles.count - 1 {
                    Divider()
                }
            }
        }
    }

    // MARK: Actions

    private func createMode() {
        let custom = CustomMode(name: "New Mode", promptText: "", notesTemplate: "Notes\n-\n")
        context.insert(custom)
        try? context.save()
        selectedID = custom.idString
        searchText = ""
    }

    private func customize(_ mode: ModeDefinition) {
        let custom = CustomMode(name: "\(mode.name) (Copy)", promptText: mode.prompt, notesTemplate: mode.notesTemplate)
        context.insert(custom)
        try? context.save()
        selectedID = custom.idString
        searchText = ""
    }

    private func duplicate(_ custom: CustomMode) {
        let copy = CustomMode(name: "\(custom.name) (Copy)", promptText: custom.promptText, notesTemplate: custom.notesTemplate)
        copy.customContext = custom.customContext
        context.insert(copy)
        try? context.save()
        selectedID = copy.idString
        searchText = ""
    }

    private func delete(_ custom: CustomMode) {
        let wasActive = model.activeModeID == custom.idString
        context.delete(custom)
        try? context.save()
        if wasActive { model.activeModeID = "general" }
        selectedID = model.activeModeID
    }

    // MARK: Text helpers

    private func firstLine(of text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? ""
    }

    private func firstSentence(of text: String) -> String {
        let line = firstLine(of: text)
        guard let end = line.firstIndex(of: ".") else { return line }
        return String(line[...end])
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

// MARK: Chat

/// The Ask page as a chat, after the pattern Nils sent: a
/// thread of questions and answers about the meetings and
/// context files, an input pill at the foot with Past chats
/// inside it, and every conversation kept so it can be
/// picked up again. Retrieval and the model call are the
/// old Ask page's: rank on the Mac, answer from the best
/// material only, deep model with the live one as fallback.
/// Follow-ups ride on the conversation so far, trimmed by
/// ChatPrompt.window.
struct ChatPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @Query private var files: [ContextFile]
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @State private var thread: ChatThread?
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isAsking = false
    @State private var askError: String?
    @State private var turnFellBack = false
    @State private var showPastChats = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            messagesList
            if let askError {
                Text(askError).foregroundStyle(.red).font(.callout)
            }
            inputPill
        }
        .padding(Space.margin)
        .navigationTitle("Ask")
        .sheet(isPresented: $showPastChats) { pastChatsSheet }
        .onAppear {
            // Coming back to the page reopens the latest chat,
            // so a conversation survives a page switch.
            if thread == nil, messages.isEmpty, let latest = threads.first {
                openThread(latest)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ask anything about your meetings and context files. Everything is searched on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("New Chat", systemImage: "square.and.pencil") { newChat() }
                .buttonStyle(QuietButtonStyle())
                .disabled(messages.isEmpty && thread == nil)
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: Space.md) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if isAsking, messages.last?.text.isEmpty == true {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(Space.sm)
                }
            }
            .panelSurface()
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: messages.last?.text) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation(RailTiming.glide) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Nothing asked yet. Questions search every meeting and context file on this Mac, and follow-ups remember the conversation.")
                .foregroundStyle(.secondary)
            ForEach(examples, id: \.self) { example in
                Button(example) {
                    input = example
                    send()
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var examples: [String] {
        [
            "What did we agree about the salary band?",
            "Which questions came up more than once?",
            "What are my open follow-ups?",
        ]
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .foregroundStyle(Surface.onInk)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(Surface.ink, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(message.text.isEmpty ? "Thinking..." : message.text)
                    .foregroundStyle(message.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                if !message.sources.isEmpty {
                    Text("Sources: \(message.sources.joined(separator: " · "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = message.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The input pill from Nils's screenshot: the question
    /// field, Past chats as a chip inside the pill, and a
    /// send button. Return sends too.
    private var inputPill: some View {
        HStack(spacing: Space.sm) {
            TextField("Ask anything about your meetings", text: $input)
                .textFieldStyle(.plain)
                .onSubmit(send)
            Button { showPastChats = true } label: {
                HStack(spacing: Space.xs) {
                    Text("Past chats")
                    Image(systemName: "arrow.up.forward")
                }
                .font(.callout.weight(.medium))
            }
            .buttonStyle(QuietButtonStyle())
            Button("Send", systemImage: "paperplane") { send() }
                .labelStyle(.iconOnly)
                .buttonStyle(InkButtonStyle())
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .panelSurface(radius: Radius.overlay)
    }

    private var pastChatsSheet: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Past chats")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { showPastChats = false }
                    .buttonStyle(QuietButtonStyle())
            }
            if threads.isEmpty {
                Text("No chats yet. Your conversations will collect here.")
                    .foregroundStyle(.secondary)
            } else {
                List(threads) { item in
                    HStack {
                        Button {
                            openThread(item)
                            showPastChats = false
                        } label: {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(item.title)
                                    .lineLimit(1)
                                Text("\(item.messages.count) messages · \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button("Delete", systemImage: "trash") { deleteThread(item) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(QuietButtonStyle())
                            .help("Delete this chat")
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(Space.lg)
        .frame(width: 440, height: 380)
    }

    private func openThread(_ item: ChatThread) {
        thread = item
        messages = item.messages
        askError = nil
    }

    private func newChat() {
        thread = nil
        messages = []
        input = ""
        askError = nil
    }

    private func deleteThread(_ item: ChatThread) {
        if thread?.uuid == item.uuid { newChat() }
        model.container.mainContext.delete(item)
        try? model.container.mainContext.save()
    }

    private func persist() {
        guard let thread else { return }
        thread.messagesJSON = ChatMessage.encode(messages)
        thread.updatedAt = Date.now
        try? model.container.mainContext.save()
    }

    private func send() {
        let asked = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !isAsking else { return }
        input = ""
        askError = nil
        turnFellBack = false
        if thread == nil {
            let created = ChatThread(title: String(asked.prefix(60)))
            model.container.mainContext.insert(created)
            thread = created
        }
        let history = ChatPrompt.window(messages)
        messages.append(ChatMessage(role: "user", text: asked))
        let answerID = UUID()
        messages.append(ChatMessage(id: answerID, role: "assistant", text: ""))
        persist()
        isAsking = true

        // Rank meetings and files on the Mac, then send the best of each.
        let meetingDocs = meetings.map { (name: $0.title, text: TranscriptSegment.plainText($0.segments) + "\n" + $0.summary, pinned: false) }
        let fileDocs = files.map { (name: $0.name, text: $0.text, pinned: $0.isPinned) }
        let bestMeetings = ContextRanker.rank(documents: meetingDocs, query: asked).prefix(3)
        let bestFiles = ContextRanker.rank(documents: fileDocs, query: asked).prefix(3)
        let turnSources = (bestMeetings.map(\.name) + bestFiles.map(\.name))
        var material = ""
        for doc in bestMeetings { material += "From meeting \(doc.name):\n\(doc.text.prefix(4_000))\n\n" }
        for doc in bestFiles { material += "From \(doc.name):\n\(doc.text.prefix(4_000))\n\n" }
        if material.isEmpty { material = "(Nothing in the meetings or files matches this question. Say so plainly, in one line, and do not guess.)" }

        Task {
            do {
                for try await piece in DeepWork.stream(
                    system: ChatPrompt.system,
                    user: ChatPrompt.userMessage(history: history, material: material, question: asked),
                    onFallback: { turnFellBack = true }
                ) {
                    if let index = messages.firstIndex(where: { $0.id == answerID }) {
                        messages[index].text += piece
                    }
                }
                if let index = messages.firstIndex(where: { $0.id == answerID }) {
                    messages[index].sources = turnSources
                    if turnFellBack { messages[index].note = "Answered by the live model; the deep model was unavailable." }
                    if messages[index].text.isEmpty { messages[index].text = "No answer came back." }
                }
            } catch {
                askError = error.localizedDescription
                messages.removeAll { $0.id == answerID && $0.text.isEmpty }
            }
            isAsking = false
            persist()
        }
    }
}
