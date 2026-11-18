import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import InterviewAIKit

/// Bringing an existing conversation into Meetings, the three ways
/// Hedy offers: paste a transcript, transcribe an audio or video
/// file on this Mac, or take a video link (direct media links are
/// downloaded and treated as files; YouTube links are read through
/// the captions the platform publishes, the same fallback Hedy
/// uses). An import becomes a normal meeting: transcript, summary,
/// speakers, and Ask all work on it, and the audio stays attached
/// when there is audio.
enum ImportError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

// MARK: - Creating the meeting

@MainActor
enum MeetingImporter {
    /// Insert the imported meeting, select it, and write its summary
    /// in the background, the same way a live session's stop does.
    @discardableResult
    static func createMeeting(
        model: AppModel, title: String, modeID: String,
        segments: [TranscriptSegment], startedAt: Date, duration: Double,
        audioFileName: String = ""
    ) -> Meeting {
        let meeting = Meeting(
            title: title.isEmpty ? "Imported meeting" : title,
            modeID: modeID,
            modeName: model.modeName(forID: modeID)
        )
        meeting.startedAt = startedAt
        meeting.durationSeconds = duration
        meeting.transcriptJSON = TranscriptSegment.encode(segments)
        meeting.audioFileName = audioFileName
        model.container.mainContext.insert(meeting)
        try? model.container.mainContext.save()
        model.selectedMeeting = meeting.id
        summarize(meeting: meeting)
        return meeting
    }

    /// The summary and follow-up for an imported meeting, written by
    /// the deep model when Dual-Brain is on, like a live session's.
    /// Also the Regenerate Summary path for any saved meeting: the
    /// summary is rewritten from the current transcript, so speaker
    /// renames reach it. `onDone` fires on the main actor either way.
    static func summarize(meeting: Meeting, onDone: (@MainActor () -> Void)? = nil) {
        let segments = meeting.segments
        guard !segments.isEmpty else {
            if let onDone { Task { @MainActor in onDone() } }
            return
        }
        let singleChannel = !segments.contains { $0.channel == "them" }
        let attendeeList = meeting.attendees.isEmpty ? [] : meeting.attendees.components(separatedBy: ", ")
        Task {
            let outcome = try? await DeepWork.complete(
                system: "You write meeting notes from a transcript: clear, complete, factual. Use only the transcript. No invented names, numbers, decisions, or roles.",
                user: PromptBuilder.summaryMessage(
                    transcript: segments, notes: meeting.notes, title: meeting.title,
                    attendees: attendeeList, singleChannel: singleChannel
                ),
                maxTokens: 1200
            )
            if let outcome, !outcome.text.isEmpty {
                let parts = outcome.text.components(separatedBy: "===")
                meeting.summary = SummaryCleaner.clean(parts.first ?? "")
                if parts.count > 1 {
                    meeting.followUp = SummaryCleaner.clean(parts[1])
                }
                try? meeting.modelContext?.save()
            }
            if let onDone { await MainActor.run { onDone() } }
        }
    }

    /// Speakers for an imported recording: diarize the kept audio,
    /// and when one speaker is found and a name was given at import,
    /// the numbered label becomes that name.
    static func diarize(meeting: Meeting, samples: [Float], knownSingle: String) {
        guard samples.count > 16_000 * 20 else {
            if !knownSingle.isEmpty {
                let updated = SpeakerNames.applying(segments: meeting.segments, mapping: ["Them": knownSingle])
                if updated != meeting.segments {
                    meeting.transcriptJSON = TranscriptSegment.encode(updated)
                    try? meeting.modelContext?.save()
                }
            } else if !meeting.segments.isEmpty {
                meeting.diarizationNote = DiarizationNotes.tooShort
                try? meeting.modelContext?.save()
            }
            return
        }
        let segments = meeting.segments
        Task {
            guard let ranges = try? await DiarizationRuntime.shared.diarize(samples: samples),
                  !ranges.isEmpty else {
                meeting.diarizationNote = DiarizationNotes.unavailable
                try? meeting.modelContext?.save()
                return
            }
            let windows: [(start: Double, end: Double)?] = segments.map { segment in
                guard segment.channel == "them",
                      let start = segment.startOffset, let duration = segment.duration else { return nil }
                return (start: start, end: start + duration)
            }
            let labels = SpeakerAssigner.labels(windows: windows, ranges: ranges)
            var updated = segments
            var changed = false
            for (index, label) in labels.enumerated() {
                if let label, updated[index].speakerLabel != label {
                    updated[index].speakerLabel = label
                    changed = true
                }
            }
            let themNames = Set(updated.filter { $0.channel == "them" }.map(\.speakerName))
            if themNames.count == 1, let only = themNames.first, !knownSingle.isEmpty, only != knownSingle {
                updated = SpeakerNames.applying(segments: updated, mapping: [only: knownSingle])
                changed = true
            }
            guard changed else { return }
            meeting.transcriptJSON = TranscriptSegment.encode(updated)
            try? meeting.modelContext?.save()
        }
    }

    /// Copy a recording into the meeting audio store, so the meeting
    /// keeps its playback after the original file moves on. Returns
    /// the stored file name, or empty when the copy fails.
    static func storeAudio(from url: URL) -> String {
        let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: SessionAudioStore.url(fileName: name))
            return name
        } catch {
            return ""
        }
    }
}

// MARK: - File transcription

/// A recording file becomes a transcript on this Mac: decoded to
/// 16 kHz mono, cut on pauses by the same ChunkPolicy the live
/// channels use, and run through the speech engine from Settings
/// (Apple Speech has no file path here, so files always go through
/// Parakeet or Whisper). Progress is reported as a fraction.
enum FileTranscriber {
    struct Result {
        var segments: [TranscriptSegment]
        /// Up to 30 minutes of the decoded audio, kept for speaker
        /// diarization after the import.
        var samples: [Float]
        var duration: Double
        /// The audio file the transcript came from (an export when
        /// the source was a video), for the meeting's playback.
        var playbackURL: URL?
    }

    static func transcribe(url: URL, onProgress: @escaping (Double) -> Void) async throws -> Result {
        let audioURL = try await readableAudioURL(for: url)
        let file = try AVAudioFile(forReading: audioURL)
        let sourceFormat = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0 else { throw ImportError.message("That file has no audio in it.") }
        let duration = Double(totalFrames) / sourceFormat.sampleRate
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw ImportError.message("That file's audio cannot be converted for transcription.")
        }

        var policy = ChunkPolicy()
        var buffered: [Float] = []
        var timeline: Double = 0
        var segments: [TranscriptSegment] = []
        var keptSamples: [Float] = []
        let keptCap = 16_000 * 60 * 30

        func transcribeChunk(_ chunk: [Float], start: Double) async throws {
            let text = try await transcribeSamples(chunk)
            if !text.isEmpty {
                segments += SegmentSplitter.segments(
                    text: text, chunkStart: start,
                    chunkDuration: Double(chunk.count) / 16_000
                )
            }
        }

        let blockFrames: AVAudioFrameCount = 16_384
        var lastProgress = -1.0
        while file.framePosition < totalFrames {
            if Task.isCancelled { throw CancellationError() }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: blockFrames) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            let floats = convert(buffer, converter: converter, target: target)
            if floats.isEmpty { continue }
            if keptSamples.count < keptCap {
                keptSamples += floats.prefix(keptCap - keptSamples.count)
            }
            buffered += floats
            let ready = policy.feed(blockSamples: floats.count, rms: rms(of: floats))
            let fraction = Double(file.framePosition) / Double(totalFrames)
            if fraction - lastProgress > 0.02 {
                lastProgress = fraction
                onProgress(fraction)
            }
            if ready {
                let untrimmed = buffered
                let start = timeline
                timeline += Double(untrimmed.count) / 16_000
                buffered = []
                let hadSpeech = policy.hasSpeech
                let trailing = policy.trailingSilentSamples
                policy.reset()
                if hadSpeech {
                    let keepSilence = Int(0.3 * 16_000)
                    let trim = min(max(0, trailing - keepSilence), untrimmed.count)
                    let chunk = Array(untrimmed.dropLast(trim))
                    if chunk.count >= 8_000 {
                        try await transcribeChunk(chunk, start: start)
                    }
                }
            }
        }
        if policy.hasSpeech, buffered.count >= 8_000 {
            try await transcribeChunk(buffered, start: timeline)
        }
        onProgress(1)
        guard !segments.isEmpty else {
            throw ImportError.message("No speech was found in that file. Check it plays speech, and that the speech language in Settings fits it.")
        }
        return Result(segments: segments, samples: keptSamples, duration: duration, playbackURL: audioURL)
    }

    /// One chunk through the configured engine. Parakeet is the
    /// default and the fallback for the Apple Speech setting.
    private static func transcribeSamples(_ samples: [Float]) async throws -> String {
        let defaults = UserDefaults.standard
        let kind = TranscriptionEngineKind(rawValue: defaults.string(forKey: "transcription.engine") ?? "parakeetUltra") ?? .parakeetUltra
        if kind == .whisper {
            let model = defaults.string(forKey: "transcription.whisperModel") ?? "large-v3-v20240930_626MB"
            let locale = defaults.string(forKey: "speech.locale") ?? "en-US"
            return try await WhisperRuntime.shared.transcribe(samples: samples, model: model, language: String(locale.prefix(2)))
        }
        return try await ParakeetRuntime.shared.transcribe(samples: samples)
    }

    /// The file itself when AVAudioFile can read it (the audio
    /// formats), otherwise an exported audio-only copy (the video
    /// formats), written to the temporary folder.
    private static func readableAudioURL(for url: URL) async throws -> URL {
        if (try? AVAudioFile(forReading: url)) != nil { return url }
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError.message("That file cannot be read as audio or video.")
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        session.outputURL = out
        session.outputFileType = .m4a
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw ImportError.message("That video's audio could not be extracted. \(session.error?.localizedDescription ?? "")")
        }
        return out
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat) -> [Float] {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }

    private static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return sqrt(sum / Float(samples.count))
    }
}

// MARK: - YouTube captions

/// A YouTube link imports through the captions the platform
/// publishes for the video: the watch page names the caption tracks,
/// and the track itself is fetched in the json3 format
/// CaptionSegments reads. Manual captions win over automatic ones,
/// and the speech language from Settings wins over other languages.
enum YouTubeImport {
    static func transcript(videoID: String) async throws -> (segments: [TranscriptSegment], title: String) {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoID)")!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let page = String(data: data, encoding: .utf8) else {
            throw ImportError.message("The video page could not be read.")
        }
        let title = pageTitle(in: page)
        guard let tracks = captionTracks(in: page), !tracks.isEmpty else {
            throw ImportError.message("This video has no captions to import. Download the audio or video file instead, and use Import Audio or Video File.")
        }
        let preferred = String((UserDefaults.standard.string(forKey: "speech.locale") ?? "en-US").prefix(2))
        let track = pickTrack(tracks, preferred: preferred)
        guard let base = track["baseUrl"] as? String, !base.isEmpty else {
            throw ImportError.message("This video's captions could not be read.")
        }
        let separator = base.contains("?") ? "&" : "?"
        guard let captionURL = URL(string: base + separator + "fmt=json3") else {
            throw ImportError.message("This video's captions could not be read.")
        }
        let (captionData, _) = try await URLSession.shared.data(from: captionURL)
        let segments = CaptionSegments.parse(json3: captionData)
        guard !segments.isEmpty else {
            throw ImportError.message("This video's captions are empty. Download the audio or video file instead, and use Import Audio or Video File.")
        }
        return (segments, title)
    }

    /// The "captionTracks" array out of the watch page's embedded
    /// player response, found by bracket matching that respects
    /// strings, then parsed as JSON.
    static func captionTracks(in page: String) -> [[String: Any]]? {
        guard let marker = page.range(of: "\"captionTracks\":") else { return nil }
        let rest = page[marker.upperBound...]
        guard let open = rest.firstIndex(of: "[") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = open
        while index < rest.endIndex {
            let character = rest[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    let json = String(rest[open...index])
                    guard let data = json.data(using: .utf8) else { return nil }
                    return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                }
            }
            index = rest.index(after: index)
        }
        return nil
    }

    static func pickTrack(_ tracks: [[String: Any]], preferred: String) -> [String: Any] {
        func score(_ track: [String: Any]) -> Int {
            var value = 0
            let language = (track["languageCode"] as? String ?? "").lowercased()
            let automatic = (track["kind"] as? String) == "asr"
            if !automatic { value += 4 }
            if language.hasPrefix(preferred.lowercased()) { value += 2 }
            if language.hasPrefix("en") { value += 1 }
            return value
        }
        return tracks.max { score($0) < score($1) } ?? tracks[0]
    }

    /// The video's title from the page's embedded details, unescaped
    /// as JSON. Empty when the page does not carry one.
    static func pageTitle(in page: String) -> String {
        guard let marker = page.range(of: "\"videoDetails\":") else { return "" }
        let rest = page[marker.upperBound...].prefix(4000)
        guard let titleMarker = rest.range(of: "\"title\":\"") else { return "" }
        var token = ""
        var escaped = false
        for character in rest[titleMarker.upperBound...] {
            if escaped {
                token += "\\"
                token.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                token.append(character)
            }
        }
        guard let data = ("\"" + token + "\"").data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) as? String else {
            return token
        }
        return decoded
    }
}

// MARK: - Import sheet

/// The import sheet on the Meetings page: three options across the
/// top, one small form per option, and the shared title, mode, and
/// speaker fields below. Everything runs on this Mac; the sheet
/// reports progress for the slow routes and keeps its errors here,
/// in plain words, instead of failing silently.
struct ImportMeetingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable {
        case transcript, file, link
        var label: String {
            switch self {
            case .transcript: return "Transcript"
            case .file: return "Audio or Video File"
            case .link: return "Video Link"
            }
        }
    }

    @State private var kind: Kind = .transcript
    @State private var title = ""
    @State private var modeID = "general"
    @State private var speakerName = ""
    @State private var pasteText = ""
    @State private var fileURL: URL?
    @State private var linkText = ""
    @State private var showFilePicker = false
    @State private var working = false
    @State private var progress: Double?
    @State private var statusText = ""
    @State private var errorText: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Import a Meeting")
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
                .disabled(working)
            }

            Picker("Import", selection: $kind) {
                ForEach(Kind.allCases, id: \.rawValue) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(working)

            switch kind {
            case .transcript:
                TextEditor(text: $pasteText)
                    .font(.body)
                    .frame(minHeight: 172)
                    .scrollContentBackground(.hidden)
                    .padding(Space.sm)
                    .background(Surface.inset, in: RoundedRectangle(cornerRadius: Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(Surface.controlBorder, lineWidth: 1)
                    }
                    .disabled(working)
                Text("Paste a transcript from anywhere. A line that starts with a name and a colon, like \u{201C}Alan: …\u{201D}, keeps that name as its speaker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .file:
                HStack(spacing: Space.sm) {
                    Button(fileURL == nil ? "Choose Audio or Video File…" : "Choose a Different File…") {
                        showFilePicker = true
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(working)
                    if let fileURL {
                        Text(fileURL.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                    }
                }
                Text("MP3, WAV, M4A, and other audio files, or MP4 and MOV video. The file is transcribed on this Mac with the speech engine from Settings, and the audio stays attached to the meeting for playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .link:
                TextField("Paste a YouTube link, or a direct audio or video file link", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(working)
                Text(linkHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                TextField("Meeting title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .disabled(working)
                HStack(spacing: Space.sm) {
                    Text("Mode")
                        .font(.callout)
                    Picker("Mode", selection: $modeID) {
                        ForEach(BuiltInModes.all) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(working)
                    Spacer()
                }
                if kind != .transcript {
                    TextField("Who is speaking? One name, optional", text: $speakerName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(working)
                    Text("When one person does most of the talking, their name labels the transcript. Leave it empty for a panel or when you do not know.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if working {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: Space.sm) {
                if working {
                    Button("Cancel Import") {
                        importTask?.cancel()
                        working = false
                        statusText = ""
                        progress = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                } else {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button("Import") { runImport() }
                    .buttonStyle(InkButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || !canImport)
            }
        }
        .padding(Space.xl)
        .frame(width: 560)
        .background(Surface.canvas)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .movie, .video, .mp3, .wav, .mpeg4Audio, .quickTimeMovie, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                fileURL = url
                if title.isEmpty {
                    title = url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }

    private var linkHint: String {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "YouTube links are read through the captions the platform publishes for the video, so no audio is saved with those meetings. A direct link to an audio or video file is downloaded and transcribed here."
        }
        switch ImportSource.classify(trimmed).kind {
        case .youTube:
            return "YouTube video. Its published captions become the transcript."
        case .directMedia:
            return "A direct media file. It will be downloaded and transcribed on this Mac."
        case .unsupported:
            return "That link is not supported. Use a YouTube link or a direct audio or video file link, or download the file and import it instead."
        }
    }

    private var canImport: Bool {
        switch kind {
        case .transcript:
            return !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return fileURL != nil
        case .link:
            if case .unsupported = ImportSource.classify(linkText).kind { return false }
            return !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: Running an import

    private func runImport() {
        errorText = nil
        working = true
        progress = nil
        statusText = "Starting…"
        importTask = Task { @MainActor in
            do {
                switch kind {
                case .transcript: try importTranscript()
                case .file: try await importFile()
                case .link: try await importLink()
                }
                dismiss()
            } catch is CancellationError {
                statusText = ""
            } catch {
                errorText = error.localizedDescription
            }
            working = false
            progress = nil
            importTask = nil
        }
    }

    private func importTranscript() throws {
        let segments = TranscriptImport.parse(pasteText, myName: LiveSession.myNameSetting)
        guard !segments.isEmpty else {
            throw ImportError.message("There is no transcript text to import yet.")
        }
        let words = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let lastOffset = segments.compactMap(\.startOffset).max() ?? 0
        let duration = max(lastOffset, Double(words) / 2.6)
        MeetingImporter.createMeeting(
            model: model,
            title: title.isEmpty ? "Imported transcript" : title,
            modeID: modeID,
            segments: segments,
            startedAt: Date.now,
            duration: duration
        )
    }

    private func importFile() async throws {
        guard let fileURL else { return }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let startedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date ?? Date.now
        try await transcribeIntoMeeting(url: fileURL, startedAt: startedAt, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
    }

    private func importLink() async throws {
        let (classified, url) = ImportSource.classify(linkText)
        switch classified {
        case .youTube(let videoID):
            statusText = "Reading the video's captions…"
            let result = try await YouTubeImport.transcript(videoID: videoID)
            var segments = result.segments
            let speaker = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !speaker.isEmpty {
                segments = SpeakerNames.applying(segments: segments, mapping: ["Them": speaker])
            }
            let duration = segments.compactMap { ($0.startOffset ?? 0) + ($0.duration ?? 0) }.max() ?? 0
            MeetingImporter.createMeeting(
                model: model,
                title: title.isEmpty ? (result.title.isEmpty ? "Imported video" : result.title) : title,
                modeID: modeID,
                segments: segments,
                startedAt: Date.now,
                duration: duration
            )
        case .directMedia:
            guard let url else { throw ImportError.message("That link could not be read.") }
            statusText = "Downloading the file…"
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let local = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + (url.pathExtension.isEmpty ? "mp3" : url.pathExtension))
            try FileManager.default.moveItem(at: tempURL, to: local)
            try await transcribeIntoMeeting(url: local, startedAt: Date.now, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        case .unsupported:
            throw ImportError.message("That link is not supported. Use a YouTube link or a direct audio or video file link, or download the file and import it instead.")
        }
    }

    /// The shared tail of the file and direct-link routes: transcribe,
    /// attach the audio, save the meeting, then diarize for speakers.
    private func transcribeIntoMeeting(url: URL, startedAt: Date, fallbackTitle: String) async throws {
        statusText = "Transcribing on this Mac…"
        let result = try await FileTranscriber.transcribe(url: url) { value in
            Task { @MainActor in self.progress = value }
        }
        statusText = "Saving the meeting…"
        let audioName = result.playbackURL.map { MeetingImporter.storeAudio(from: $0) } ?? ""
        let speaker = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        var segments = result.segments
        if !speaker.isEmpty {
            // A single named voice can label the lines right away;
            // diarization below still splits a panel if it finds one.
            segments = SpeakerNames.applying(segments: segments, mapping: ["Them": speaker])
        }
        let meeting = MeetingImporter.createMeeting(
            model: model,
            title: title.isEmpty ? fallbackTitle : title,
            modeID: modeID,
            segments: segments,
            startedAt: startedAt,
            duration: result.duration,
            audioFileName: audioName
        )
        MeetingImporter.diarize(meeting: meeting, samples: result.samples, knownSingle: speaker)
    }
}
