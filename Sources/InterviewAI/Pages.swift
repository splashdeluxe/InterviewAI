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
                    if session.audioRecordingActive {
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
    @AppStorage("reading.transcriptFontSize") private var transcriptFontSize = 14.0

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
                            copyText(TranscriptSegment.plainText(meeting.segments))
                        }
                        .disabled(meeting.segments.isEmpty)
                        Button("Export…") {
                            saveTextFile(
                                TranscriptExport.markdown(title: meeting.title, date: meeting.startedAt, attendees: attendeeList, location: locationLabel, segments: meeting.segments, summary: meeting.summary),
                                fileName: TranscriptExport.fileName(title: meeting.title, date: meeting.startedAt)
                            )
                        }
                        .disabled(meeting.segments.isEmpty)
                        Button(meeting.eventID.isEmpty ? "Link to Calendar Event…" : "Change Calendar Event…") {
                            showEventPicker = true
                        }
                    }
                }
                .sheet(isPresented: $showEventPicker) {
                    MeetingEventPicker(meeting: meeting) { event in
                        model.setCalendarEvent(event, for: meeting)
                        showEventPicker = false
                    }
                }
                if !meeting.audioFileName.isEmpty, SessionAudioStore.exists(fileName: meeting.audioFileName) {
                    MeetingAudioPlayer(url: SessionAudioStore.url(fileName: meeting.audioFileName))
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
                            if meeting.summary.isEmpty {
                                Text("No summary yet. It is written when the call stops, if a model is reachable.")
                            } else {
                                DocTextView(text: meeting.summary)
                            }
                            if !meeting.followUp.isEmpty {
                                Text("Follow-Up Draft").font(.headline)
                                DocTextView(text: meeting.followUp)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                default:
                    ScrollView {
                        TranscriptBlock(segments: meeting.segments, fontSize: transcriptFontSize)
                    }
                }
            }
            .padding(Space.margin)
        } else {
            ContentUnavailableView("No Meeting Selected", systemImage: "sidebar.right")
        }
    }
}

/// Plays a meeting's saved session audio, recorded with the other
/// side on the left and you on the right, and offers the file itself
/// in Finder for anything the player cannot do.
struct MeetingAudioPlayer: View {
    let url: URL
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
    }

    private func setUp() {
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
    @State private var deepNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
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
            if let deepNote {
                Text(deepNote).foregroundStyle(.secondary).font(.callout)
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
        deepNote = nil
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
        if contextText.isEmpty { contextText = "(Nothing in the meetings or files matches this question. Say so plainly, in one line, and do not guess.)" }

        Task {
            do {
                for try await piece in DeepWork.stream(
                    system: "You answer questions about the user's own meetings and files. Use only the material given, and say plainly when it does not cover the question. Name the meeting or file each fact came from. Answer directly, in the language of the question.",
                    user: "Material:\n\(contextText)\n\nQuestion: \(asked)",
                    onFallback: { deepNote = "Answered by the live model; the deep model was unavailable." }
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
