import Foundation
import SwiftData
import InterviewAIKit

/// One saved call.
@Model
final class Meeting {
    var title: String
    var startedAt: Date = Date.now
    var durationSeconds: Double = 0
    var modeID: String = "general"
    var modeName: String = "General"
    /// TranscriptSegment list as JSON, see TranscriptSegment.encode.
    var transcriptJSON: String = "[]"
    var notes: String = ""
    var summary: String = ""
    var followUp: String = ""
    /// Calendar event identifier when the session was matched to an
    /// event, whether it was started from it or found by its time.
    var eventID: String = ""
    /// The people invited to the calendar event, comma-joined.
    var attendees: String = ""
    var calendarName: String = ""
    var eventLocation: String = ""
    /// The event's own notes or description, plus its URL when it has one.
    var eventDetails: String = ""
    var eventStart: Date?
    var eventEnd: Date?
    var uuid: UUID = UUID()

    init(title: String, modeID: String, modeName: String) {
        self.title = title
        self.modeID = modeID
        self.modeName = modeName
    }

    var segments: [TranscriptSegment] { TranscriptSegment.decode(transcriptJSON) }
}

@Model
final class ContextFile {
    var name: String
    /// resume, job, notes, or general, guessed from the file name.
    var kind: String = "general"
    var text: String = ""
    var isPinned: Bool = false
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()

    init(name: String, kind: String, text: String, isPinned: Bool) {
        self.name = name
        self.kind = kind
        self.text = text
        self.isPinned = isPinned
    }

    static func kind(forName name: String) -> String {
        ContextClassifier.kind(forName: name)
    }

    /// Name first, text second, so a resume named after its owner is
    /// still recognised as a resume. See ContextClassifier.
    static func classify(name: String, text: String) -> String {
        ContextClassifier.kind(forName: name, text: text)
    }
}

/// A mode the user added. Built-in modes live in BuiltInModes.
@Model
final class CustomMode {
    var name: String
    var promptText: String = ""
    var notesTemplate: String = ""
    var customContext: String = ""
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()

    init(name: String, promptText: String, notesTemplate: String = "") {
        self.name = name
        self.promptText = promptText
        self.notesTemplate = notesTemplate
    }

    var idString: String { "custom-\(uuid.uuidString)" }
}

/// One generated Intelligence document: a profile, talking points for a
/// job description, a company brief, or a cover letter.
@Model
final class IntelligenceDoc {
    /// profile, talkingPoints, companyIntel, or coverLetter.
    var kind: String = "profile"
    /// What it was made from, e.g. the job description's file name.
    var label: String = ""
    var text: String = ""
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()

    init(kind: String, label: String, text: String) {
        self.kind = kind
        self.label = label
        self.text = text
    }

    var kindTitle: String {
        switch kind {
        case "profile": return "About You"
        case "talkingPoints": return "Talking Points"
        case "companyIntel": return "Company Intel"
        case "coverLetter": return "Cover Letter"
        case "instructions": return "Instructions"
        case "extraInfo": return "More About You"
        default: return kind
        }
    }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case live, meetings, modes, context, intelligence, ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .meetings: "Meetings"
        case .modes: "Modes"
        case .context: "Context"
        case .intelligence: "Profile"
        case .ask: "Ask"
        }
    }

    var symbol: String {
        switch self {
        case .live: "waveform"
        case .meetings: "clock.arrow.circlepath"
        case .modes: "person.wave.2"
        case .context: "doc.text"
        case .intelligence: "person.text.rectangle"
        case .ask: "magnifyingglass"
        }
    }
}

/// Provider settings, read from UserDefaults. The key is not here: it is
/// in the Keychain under "provider-key".
enum ProviderSettings {
    static func config() -> BrainConfig {
        let defaults = UserDefaults.standard
        let kind = BrainConfig.Kind(rawValue: defaults.string(forKey: "provider.kind") ?? "ollama") ?? .ollama
        let base = defaults.string(forKey: "provider.baseURL") ?? (kind == .ollama ? "http://localhost:11434" : "https://api.openai.com")
        let model = defaults.string(forKey: "provider.model") ?? (kind == .ollama ? "llama3.2:1b" : "gpt-4o-mini")
        return BrainConfig(kind: kind, baseURL: base, model: model, visionModel: defaults.bool(forKey: "provider.vision"))
    }

    static var apiKey: String { KeychainStore.get(account: "provider-key") }

    /// Dual-Brain: a second, bigger model for the work done outside
    /// a live call. Off unless the user turns it on in Settings,
    /// Providers; the deep name defaults like the live one does.
    static var dualBrain: Bool { UserDefaults.standard.bool(forKey: "provider.dualBrain") }

    static var deepModel: String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "provider.deepModel"), !stored.isEmpty { return stored }
        let kind = BrainConfig.Kind(rawValue: defaults.string(forKey: "provider.kind") ?? "ollama") ?? .ollama
        return kind == .ollama ? BrainRouting.defaultDeepModel : ""
    }

    /// The config a task runs on: live tasks and a Dual-Brain-off
    /// install get the live config untouched; deep tasks get the
    /// Deep model when Dual-Brain is on.
    static func config(for task: BrainTask) -> BrainConfig {
        BrainRouting.resolve(task: task, dualBrain: dualBrain, live: config(), deepModel: deepModel)
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var sidebar: SidebarItem? = .live
    var selectedMeeting: PersistentIdentifier?
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    let session = LiveSession()
    let overlay = OverlayController()
    let phoneDisplay = PhoneDisplay()

    /// Whether the menu bar icon is inserted. Held on the model, NOT in
    /// an @AppStorage in the App struct: the MenuBarExtra isInserted
    /// binding wrote the default back during scene setup, and that
    /// write re-triggered scene setup — a loop that pegged the CPU and
    /// starved the main window before it ever appeared (the v1.4.0
    /// "not running anymore" bug, fixed in 1.4.1). The write below
    /// happens only on a real change.
    var showMenuBarIcon: Bool = UserDefaults.standard.object(forKey: "general.showMenuBarIcon") as? Bool ?? true {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            UserDefaults.standard.set(showMenuBarIcon, forKey: "general.showMenuBarIcon")
        }
    }

    /// The phone display (C-lite): a local-network web page mirroring
    /// the live session to a phone browser. Off by default; the didSet
    /// starts and stops the little server.
    var phoneDisplayEnabled: Bool = UserDefaults.standard.object(forKey: "phoneDisplay.enabled") as? Bool ?? false {
        didSet {
            guard phoneDisplayEnabled != oldValue else { return }
            UserDefaults.standard.set(phoneDisplayEnabled, forKey: "phoneDisplay.enabled")
            phoneDisplay.apply(enabled: phoneDisplayEnabled)
        }
    }

    /// The active mode id: a built-in id or a custom mode's idString.
    var activeModeID: String = UserDefaults.standard.string(forKey: "mode.active") ?? "looking-for-work" {
        didSet { UserDefaults.standard.set(activeModeID, forKey: "mode.active") }
    }

    init(container: ModelContainer) {
        self.container = container
        session.model = self
        overlay.model = self
        phoneDisplay.bind(session: session)
        if phoneDisplayEnabled { phoneDisplay.apply(enabled: true) }
        HotkeyCenter.shared.model = self
        HotkeyCenter.shared.registerAll()
        reclassifyStoredContextFiles()
    }

    // MARK: Modes

    func customModes() -> [CustomMode] {
        (try? container.mainContext.fetch(FetchDescriptor<CustomMode>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    /// The active mode as a definition plus its custom context.
    func activeMode() -> (definition: ModeDefinition, context: String) {
        if let custom = customModes().first(where: { $0.idString == activeModeID }) {
            return (ModeDefinition(id: custom.idString, name: custom.name, prompt: custom.promptText, notesTemplate: custom.notesTemplate), custom.customContext)
        }
        let definition = BuiltInModes.mode(id: activeModeID)
        return (definition, UserDefaults.standard.string(forKey: "mode.context.\(definition.id)") ?? "")
    }

    func setModeContext(_ text: String, forModeID id: String) {
        if let custom = customModes().first(where: { $0.idString == id }) {
            custom.customContext = text
            try? container.mainContext.save()
        } else {
            UserDefaults.standard.set(text, forKey: "mode.context.\(id)")
        }
    }

    func modeName(forID id: String) -> String {
        if let custom = customModes().first(where: { $0.idString == id }) { return custom.name }
        return BuiltInModes.mode(id: id).name
    }

    // MARK: Context for prompts

    /// The profile layer for live answers, in the order it should be
    /// read: the user's standing instructions first, then their extra
    /// background, then the newest talking points for the target role.
    /// Each part is capped, so a long profile cannot crowd out the call.
    func profileContext() -> String {
        let docs = (try? container.mainContext.fetch(FetchDescriptor<IntelligenceDoc>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        func newest(_ kind: String) -> String {
            docs.first(where: { $0.kind == kind })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var parts: [String] = []
        let instructions = newest("instructions")
        if !instructions.isEmpty { parts.append("Instructions for every answer:\n" + String(instructions.prefix(1500))) }
        let extra = newest("extraInfo")
        if !extra.isEmpty { parts.append("More about me:\n" + String(extra.prefix(1500))) }
        let points = newest("talkingPoints")
        if !points.isEmpty { parts.append("Talking points for the target role:\n" + String(points.prefix(4000))) }
        return parts.joined(separator: "\n\n")
    }

    func contextDocuments() -> [(name: String, text: String, pinned: Bool)] {
        let files = (try? container.mainContext.fetch(FetchDescriptor<ContextFile>())) ?? []
        return files.map { (name: $0.name, text: $0.text, pinned: $0.isPinned) }
    }

    func addContextFile(name: String, text: String) {
        let kind = ContextFile.classify(name: name, text: text)
        let pinned = kind == "resume" || kind == "job"
        container.mainContext.insert(ContextFile(name: name, kind: kind, text: text, isPinned: pinned))
        try? container.mainContext.save()
    }

    /// Files stored before the text-aware classifier existed can sit
    /// at kind "general" forever (a resume named after its owner never
    /// matched the name rules, so the Profile pickers never offered
    /// it). Re-run the classifier over those files once. Kinds set by
    /// hand later are never touched: the pass runs a single time.
    func reclassifyStoredContextFiles() {
        let key = "context.reclassified.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let files = (try? container.mainContext.fetch(FetchDescriptor<ContextFile>())) ?? []
        var changed = false
        for file in files where file.kind == "general" {
            let kind = ContextFile.classify(name: file.name, text: file.text)
            if kind == "resume" || kind == "job" {
                file.kind = kind
                file.isPinned = true
                changed = true
            }
        }
        if changed { try? container.mainContext.save() }
    }

    // MARK: Meetings

    @discardableResult
    func saveMeeting(from session: LiveSession) -> Meeting {
        let mode = activeMode()
        let started = session.startedAt ?? Date.now
        // The calendar event names the meeting and brings its people,
        // whether the session was started from the event or just ran
        // while the event was on. Without a match the meeting keeps
        // the composed mode-and-time title.
        let event = session.linkedEvent ?? CalendarService.event(
            overlappingSessionStart: started,
            end: started.addingTimeInterval(session.duration)
        )
        let meeting = Meeting(
            title: event?.title ?? session.meetingTitle,
            modeID: mode.definition.id,
            modeName: mode.definition.name
        )
        meeting.startedAt = started
        meeting.durationSeconds = session.duration
        meeting.transcriptJSON = TranscriptSegment.encode(session.finalSegments)
        meeting.notes = session.notes
        if let event {
            stamp(meeting, with: event)
        }
        container.mainContext.insert(meeting)
        try? container.mainContext.save()
        selectedMeeting = meeting.id
        return meeting
    }

    /// Put a calendar event's name and people on a meeting: the title,
    /// who was invited, where, and the event's own notes.
    private func stamp(_ meeting: Meeting, with event: UpcomingEvent) {
        meeting.title = event.title
        meeting.eventID = event.id
        meeting.attendees = event.attendees.joined(separator: ", ")
        meeting.calendarName = event.calendarName
        meeting.eventLocation = event.location
        var details = event.details
        if !event.url.isEmpty {
            details = details.isEmpty ? event.url : details + "\n" + event.url
        }
        meeting.eventDetails = details
        meeting.eventStart = event.start
        meeting.eventEnd = event.end
    }

    /// The user picking which calendar event a saved meeting was, from
    /// its history. An event renames the meeting and brings its people;
    /// nil takes the link away and the meeting goes back to its
    /// composed mode-and-time title. The calendar itself is never
    /// touched, only the saved meeting.
    func setCalendarEvent(_ event: UpcomingEvent?, for meeting: Meeting) {
        if let event {
            stamp(meeting, with: event)
        } else {
            meeting.eventID = ""
            meeting.attendees = ""
            meeting.calendarName = ""
            meeting.eventLocation = ""
            meeting.eventDetails = ""
            meeting.eventStart = nil
            meeting.eventEnd = nil
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            meeting.title = "\(meeting.modeName) · \(formatter.string(from: meeting.startedAt))"
        }
        try? container.mainContext.save()
    }
}
