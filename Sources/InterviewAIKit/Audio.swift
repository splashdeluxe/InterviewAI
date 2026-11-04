import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import FluidAudio
import ScreenCaptureKit
import Speech
import WhisperKit

/// Permission states, shown on the Permissions tab.
public enum PermissionState {
    public static func speech() -> String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    public static func microphone() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    /// Preflight asks the system without side effects: it never raises
    /// the permission dialog. Probing with the shareable content list
    /// instead made macOS ask again on every check.
    public static func screenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func screenRecording() async -> String {
        screenRecordingGranted() ? "Granted" : "Not granted"
    }

    public static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Which engine turns audio into text, chosen in Settings, Speech.
/// Parakeet Ultra is the default: Moondream's post-trained Parakeet v3,
/// run on the Neural Engine through FluidAudio. It is the fastest of the
/// three and the most accurate on its 25 European languages, but it does
/// not cover Indonesian. Whisper runs the local WhisperKit models (the
/// engine family Handy uses through whisper.cpp): wider language cover,
/// slower, chunk-wise results. Apple Speech is the light built-in.
public enum TranscriptionEngineKind: String, Sendable {
    case parakeetUltra
    case appleSpeech
    case whisper
}

/// One transcription channel: capture code feeds it PCM buffers, it
/// emits (channel, text, isFinal) through the engine's callbacks.
protocol AudioChanneling: AnyObject {
    func start()
    func stop()
    func append(_ buffer: AVAudioPCMBuffer)
}

/// Two-channel capture and on-device transcription. System audio is the
/// other side ("them"), the microphone is "me". Nothing is recorded to
/// disk. Apple Speech tasks end on silence, so each channel rotates its
/// task after every final result or error.
public final class AudioEngine: @unchecked Sendable {
    /// (channel, text, isFinal, audioSeconds). The last value is how many
    /// seconds of audio the line covers, when the engine knows it.
    public var onSegment: ((String, String, Bool, Double?) -> Void)?
    public var onStatus: ((String) -> Void)?

    private var themChannel: AudioChanneling?
    private var meChannel: AudioChanneling?
    private var stream: SCStream?
    private var tap: SystemAudioTap?
    private var engine: AVAudioEngine?
    private var collector: ThemCollector?
    /// The Screen Recording ask goes out at most once per launch, and
    /// only through the proper API, never as a side effect of a check.
    private var screenAskUsed = false
    private(set) public var isRunning = false

    public init() {}

    /// The other side's audio, 16 kHz mono, kept in memory while a
    /// session runs with speaker identification on. Never saved to disk;
    /// read it after stop to diarize, then it is dropped on next start.
    public var themAudio: [Float] { collector?.snapshot() ?? [] }

    public func start(localeIdentifier: String,
                      engine engineKind: TranscriptionEngineKind = .appleSpeech,
                      whisperModel: String = "large-v3-v20240930_626MB",
                      diarize: Bool = false) {
        guard !isRunning else { return }
        collector = diarize ? ThemCollector() : nil
        let emit: (String, String, Bool, Double?) -> Void = { [weak self] ch, text, final, seconds in
            self?.onSegment?(ch, text, final, seconds)
        }
        let status: (String) -> Void = { [weak self] message in self?.onStatus?(message) }
        let them: AudioChanneling
        let me: AudioChanneling
        switch engineKind {
        case .appleSpeech:
            let locale = Locale(identifier: localeIdentifier)
            guard let themSpeech = SpeechChannel(name: "them", locale: locale, emit: emit),
                  let meSpeech = SpeechChannel(name: "me", locale: locale, emit: emit) else {
                onStatus?("Speech recognizer is not available for \(localeIdentifier).")
                return
            }
            them = themSpeech
            me = meSpeech
        case .whisper:
            let language = String(localeIdentifier.prefix(2))
            them = WhisperChannel(name: "them", model: whisperModel, language: language, emit: emit, onStatus: status)
            me = WhisperChannel(name: "me", model: whisperModel, language: language, emit: emit, onStatus: status)
        case .parakeetUltra:
            them = ParakeetChannel(name: "them", emit: emit, onStatus: status)
            me = ParakeetChannel(name: "me", emit: emit, onStatus: status)
        }
        themChannel = them
        meChannel = me
        isRunning = true

        Task {
            if engineKind == .appleSpeech {
                let speechOK = await PermissionState.requestSpeech()
                guard speechOK else {
                    onStatus?("Speech Recognition is not granted. Open the Permissions tab.")
                    return
                }
            }
            them.start()
            me.start()
            await startSystemAudio(them: them, collector: collector)
            joinMicrophone(me: me)
        }
    }

    /// The microphone joins without ever blocking the other side.
    /// A first-run mic prompt can sit unanswered (or behind another
    /// app), and awaiting it in the start sequence held the whole
    /// session at "Starting" with nothing heard. A granted mic starts
    /// at once; an unasked mic asks in the background and joins when
    /// allowed, if that same session is still running; a denied mic
    /// just posts the plain status.
    private func joinMicrophone(me: AudioChanneling) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startMicrophone(me: me)
        case .notDetermined:
            Task { [weak self] in
                let granted = await PermissionState.requestMicrophone()
                guard granted, let self, self.isRunning,
                      let me = self.meChannel else { return }
                self.startMicrophone(me: me)
            }
        default:
            onStatus?("Microphone is not granted. The other side will still be transcribed.")
        }
    }

    public func stop() {
        isRunning = false
        themChannel?.stop()
        meChannel?.stop()
        themChannel = nil
        meChannel = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        if let stream {
            Task { try? await stream.stopCapture() }
        }
        stream = nil
        tap = nil
    }

    private func startMicrophone(me: AudioChanneling) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            onStatus?("No microphone input found.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            me.append(buffer)
        }
        engine.prepare()
        self.engine = engine
        do {
            try engine.start()
        } catch {
            onStatus?("Microphone failed: \(error.localizedDescription)")
        }
    }

    private func startSystemAudio(them: AudioChanneling, collector: ThemCollector?) async {
        // macOS ties the Screen Recording grant to the exact binary, so
        // a rebuilt app reads as not granted even when an older build was
        // allowed. Check without side effects first; ask once per launch
        // through the proper API; if it stays ungranted, say so and stop
        // instead of letting the capture ask again on every start.
        if !PermissionState.screenRecordingGranted() {
            if !screenAskUsed {
                screenAskUsed = true
                _ = CGRequestScreenCaptureAccess()
                // Land the user on the exact list where the tick goes
                // instead of leaving them to hunt for it.
                if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(pane)
                }
            }
            guard PermissionState.screenRecordingGranted() else {
                onStatus?("Screen Recording is not granted for this build yet, so the other side cannot be heard. Allow InterviewAI under Privacy and Security, Screen Recording, then quit and reopen the app. If it is already ticked, untick it and tick it again for this build.")
                return
            }
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                onStatus?("No display found for system audio capture.")
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.showsCursor = false
            let tap = SystemAudioTap(channel: them, collector: collector)
            tap.onProblem = { [weak self] message in self?.onStatus?(message) }
            // The tap is also the stream delegate, so a stream that dies
            // mid-call reports why instead of going quiet.
            let stream = SCStream(filter: filter, configuration: config, delegate: tap)
            try stream.addStreamOutput(tap, type: .audio, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
            try await stream.startCapture()
            self.stream = stream
            self.tap = tap
            onStatus?("Listening")
            // A stream can start cleanly and still deliver nothing (a
            // grant bound to another build, an audio route change). If
            // no buffer has arrived after a few seconds, say so: a dead
            // capture looks exactly like a quiet call otherwise.
            Task { [weak self, weak tap] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, self.isRunning, let tap, tap.receivedBuffers == 0 else { return }
                self.onStatus?("System audio capture started, but no audio has arrived yet. If the other side is talking, this build may be missing the Screen Recording grant. Check the Permissions tab.")
            }
        } catch {
            onStatus?("System audio failed. Grant Screen Recording in the Permissions tab. (\(error.localizedDescription))")
        }
    }
}

final class SpeechChannel: AudioChanneling, @unchecked Sendable {
    let name: String
    let recognizer: SFSpeechRecognizer
    private let emit: (String, String, Bool, Double?) -> Void
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var stopped = false

    init?(name: String, locale: Locale, emit: @escaping (String, String, Bool, Double?) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { return nil }
        self.name = name
        self.recognizer = recognizer
        self.emit = emit
    }

    func start() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        lock.lock()
        self.request = request
        lock.unlock()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                emit(name, result.bestTranscription.formattedString, result.isFinal, nil)
                if result.isFinal { rotate() }
            } else if error != nil {
                rotate()
            }
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        request?.endAudio()
        request = nil
        lock.unlock()
        task?.cancel()
        task = nil
    }

    private func rotate() {
        lock.lock()
        let isStopped = stopped
        lock.unlock()
        guard !isStopped else { return }
        task?.cancel()
        task = nil
        lock.lock()
        request = nil
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            lock.lock()
            let stillStopped = stopped
            lock.unlock()
            if !stillStopped { start() }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }
}

final class SystemAudioTap: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let channel: AudioChanneling
    let collector: ThemCollector?
    /// Capture problems the user should see (unreadable buffers, a
    /// stream that stopped). Wired to the session status by AudioEngine.
    var onProblem: ((String) -> Void)?
    /// How many audio buffers the stream has delivered. The engine
    /// watches this after start: zero means the capture is dead even
    /// though it started without an error.
    private(set) var receivedBuffers = 0
    private var convertedBuffers = 0
    private var failedBuffers = 0
    private var problemReported = false

    init(channel: AudioChanneling, collector: ThemCollector? = nil) {
        self.channel = channel
        self.collector = collector
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferIsValid(sampleBuffer) else { return }
        receivedBuffers += 1
        if let pcm = Self.pcmBuffer(from: sampleBuffer) {
            convertedBuffers += 1
            channel.append(pcm)
            collector?.append(pcm)
        } else {
            // A buffer that cannot be read is dropped, but not in
            // silence: if they all fail, the session status says so.
            failedBuffers += 1
            if failedBuffers >= 10, convertedBuffers == 0, !problemReported {
                problemReported = true
                onProblem?("System audio is arriving but cannot be read, so the other side will not be transcribed. Restart the app; if it repeats, note the macOS version and report it.")
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onProblem?("System audio capture stopped: \(error.localizedDescription)")
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: streamDescription) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}

/// Collects the other side's audio as 16 kHz mono floats while a
/// session runs, so speakers can be identified when it ends. Memory
/// only, capped at one hour; past the cap it simply stops collecting
/// and the first hour still gets diarized.
final class ThemCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var samples: [Float] = []
    private let cap = 16_000 * 60 * 60

    func append(_ buffer: AVAudioPCMBuffer) {
        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        let status = converter.convert(to: out, error: nil) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
        let floats = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        lock.lock()
        if samples.count < cap {
            samples.append(contentsOf: floats.prefix(cap - samples.count))
        }
        lock.unlock()
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

/// When a Whisper channel should cut its buffered audio and transcribe.
/// Pure sample counting, so it is unit tested without audio hardware.
/// The rule is Handy's shape, shrunk: keep speech together, cut on a
/// real pause, never let a chunk grow past the hard cap.
public struct ChunkPolicy: Sendable {
    /// RMS under this counts as silence (about -44 dBFS).
    public static let silenceRMS: Float = 0.006
    public static let sampleRate = 16_000
    /// Cut once this much audio is buffered and a pause arrives.
    /// 2.5 s (was 4.0): a line lands about two seconds sooner, which
    /// is the difference between a transcript that feels live and one
    /// that feels stuck.
    public static let minChunkSeconds = 2.5
    /// Cut no matter what once this much audio is buffered.
    public static let maxChunkSeconds = 15.0
    /// The pause that ends a chunk. 0.6 s (was 0.9): a natural breath
    /// ends most spoken sentences.
    public static let pauseSeconds = 0.6

    private(set) public var bufferedSamples = 0
    private(set) public var trailingSilentSamples = 0
    private(set) public var hasSpeech = false

    public init() {}

    public var bufferedSeconds: Double { Double(bufferedSamples) / Double(Self.sampleRate) }
    public var trailingSilentSeconds: Double { Double(trailingSilentSamples) / Double(Self.sampleRate) }

    /// Feed one converted block. Returns true when the buffer should be
    /// transcribed now (the caller drains it, then calls `reset()`).
    public mutating func feed(blockSamples: Int, rms: Float) -> Bool {
        bufferedSamples += blockSamples
        if rms >= Self.silenceRMS {
            trailingSilentSamples = 0
            hasSpeech = true
        } else {
            trailingSilentSamples += blockSamples
        }
        if bufferedSeconds >= Self.maxChunkSeconds { return true }
        return hasSpeech && bufferedSeconds >= Self.minChunkSeconds && trailingSilentSeconds >= Self.pauseSeconds
    }

    public mutating func reset() {
        bufferedSamples = 0
        trailingSilentSamples = 0
        hasSpeech = false
    }
}

/// Isolation for the Whisper pipeline. WhisperKit's pipeline class is
/// not Sendable, so every touch of it happens on this one global actor:
/// calls stay serial, which the CoreML models handle best, and no
/// pipeline value ever crosses an isolation boundary.
@globalActor
public actor WhisperIsolation {
    public static let shared = WhisperIsolation()
}

/// The shared WhisperKit pipeline. One model instance serves both
/// channels. Loading downloads the model on first use.
@WhisperIsolation
public final class WhisperRuntime {
    public nonisolated static let shared = WhisperRuntime()

    // WhisperKit's transcribe is @concurrent, so Swift will not let an
    // actor-isolated pipeline be passed to it. The reference is marked
    // nonisolated(unsafe) and is only ever touched from WhisperIsolation
    // methods, which keeps access serial by construction.
    private nonisolated(unsafe) var pipe: WhisperKit?
    private var loadedModel: String?

    /// Nonisolated so the shared instance can be created anywhere; the
    /// stored properties start empty and are only touched on the actor.
    nonisolated init() {}

    /// Download (first time) and load a model, ready to transcribe.
    public func prepare(model: String) async throws {
        try await loadIfNeeded(model: model)
    }

    public func transcribe(samples: [Float], model: String, language: String) async throws -> String {
        try await loadIfNeeded(model: model)
        guard let pipe else { throw BrainError.empty }
        var options = DecodingOptions()
        options.language = language
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // Whisper answers pure silence with a marker, not with words.
        if text == "[BLANK_AUDIO]" || text == "(silence)" { return "" }
        return text
    }

    private func loadIfNeeded(model: String) async throws {
        if pipe != nil, loadedModel == model { return }
        pipe = try await WhisperKit(WhisperKitConfig(model: model))
        loadedModel = model
    }
}

/// A channel that transcribes with Whisper instead of Apple Speech.
/// Audio is converted to 16 kHz mono, buffered, and cut by ChunkPolicy;
/// each cut is transcribed and emitted as one final segment. Whisper
/// gives no partials, so the transcript grows in sentence-size steps.
final class WhisperChannel: AudioChanneling, @unchecked Sendable {
    let name: String
    private let model: String
    private let language: String
    private let emit: (String, String, Bool, Double?) -> Void
    private let onStatus: (String) -> Void

    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var samples: [Float] = []
    private var policy = ChunkPolicy()
    private var stopped = false
    private var chain: Task<Void, Never>?

    private var convertFailures = 0
    private var convertSuccesses = 0
    private var convertProblemReported = false

    /// Conversion failures used to return an empty block, which the
    /// caller drops without a word: a channel could eat every buffer
    /// for a whole call and look merely quiet. Count them, and say so
    /// once when nothing at all converts.
    private func noteConvertFailure() {
        convertFailures += 1
        if convertFailures >= 30, convertSuccesses == 0, !convertProblemReported {
            convertProblemReported = true
            onStatus("Audio from the \(name == "them" ? "other side" : "microphone") cannot be converted for transcription, so nothing will be heard from it.")
        }
    }

    init(name: String, model: String, language: String,
         emit: @escaping (String, String, Bool, Double?) -> Void, onStatus: @escaping (String) -> Void) {
        self.name = name
        self.model = model
        self.language = language
        self.emit = emit
        self.onStatus = onStatus
    }

    func start() {
        let model = self.model
        let onStatus = self.onStatus
        Task {
            do {
                try await WhisperRuntime.shared.prepare(model: model)
                onStatus("Listening (Whisper)")
            } catch {
                onStatus("Whisper model failed to load: \(error.localizedDescription). Check the network for the first download, or switch back to Apple Speech in Settings, Speech.")
            }
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let tail = samples
        let hadSpeech = policy.hasSpeech
        samples = []
        policy.reset()
        lock.unlock()
        chain?.cancel()
        chain = nil
        // A last spoken fragment still counts.
        if hadSpeech, tail.count >= ChunkPolicy.sampleRate / 2 {
            let name = self.name, model = self.model, language = self.language, emit = self.emit
            Task {
                if let text = try? await WhisperRuntime.shared.transcribe(samples: tail, model: model, language: language), !text.isEmpty {
                    emit(name, text, true, Double(tail.count) / 16_000)
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let floats = convert(buffer)
        guard !floats.isEmpty else { return }
        let rms = Self.rms(of: floats)
        lock.lock()
        if stopped { lock.unlock(); return }
        samples.append(contentsOf: floats)
        let ready = policy.feed(blockSamples: floats.count, rms: rms)
        var chunk: [Float]?
        if ready {
            if policy.hasSpeech {
                // Keep the tail of the pause out of the model's ear.
                let keepSilence = Int(0.3 * Double(ChunkPolicy.sampleRate))
                let trim = min(policy.trailingSilentSamples - keepSilence, samples.count)
                chunk = Array(samples.dropLast(max(0, trim)))
            }
            samples = []
            policy.reset()
        }
        lock.unlock()
        if let chunk, chunk.count >= ChunkPolicy.sampleRate / 2 {
            enqueue(chunk)
        }
    }

    private func enqueue(_ chunk: [Float]) {
        let name = self.name, model = self.model, language = self.language, emit = self.emit
        let previous = chain
        chain = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            if let text = try? await WhisperRuntime.shared.transcribe(samples: chunk, model: model, language: language), !text.isEmpty {
                emit(name, text, true, Double(chunk.count) / 16_000)
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else {
            noteConvertFailure()
            return []
        }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return [] }
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
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else {
            noteConvertFailure()
            return []
        }
        convertSuccesses += 1
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }

    static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return sqrt(sum / Float(samples.count))
    }
}

/// Isolation for the Parakeet pipeline, same pattern as Whisper: one
/// serial place touches the model, which Core ML handles best.
@globalActor
public actor ParakeetIsolation {
    public static let shared = ParakeetIsolation()
}

/// The shared Parakeet Ultra model (FluidAudio, Core ML on the Neural
/// Engine). One instance serves both channels. Loading downloads the
/// model (about 650 MB) on first use from Hugging Face.
@ParakeetIsolation
public final class ParakeetRuntime {
    public nonisolated static let shared = ParakeetRuntime()

    private var manager: AsrManager?
    private var loaded = false

    nonisolated init() {}

    /// Download (first time) and load Parakeet Ultra, ready to transcribe.
    public func prepare() async throws {
        if loaded { return }
        let models = try await AsrModels.downloadAndLoad(version: .ultra)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        loaded = true
    }

    /// Samples are 16 kHz mono floats. Parakeet works out the language
    /// itself (25 European languages), so no language is passed.
    public func transcribe(samples: [Float]) async throws -> String {
        try await prepare()
        guard let manager else { throw BrainError.empty }
        // This FluidAudio version wants a decoder state per call. Each
        // chunk here is a finished utterance, so it gets a fresh one.
        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A channel that transcribes with Parakeet Ultra instead of Apple
/// Speech or Whisper. Same shape as the Whisper channel: audio is
/// converted to 16 kHz mono, buffered, and cut by ChunkPolicy (whose
/// 15 s cap matches Parakeet's window). Each cut is transcribed and
/// emitted as one final segment, so lines land in sentence-size steps,
/// only much faster than Whisper: Parakeet runs at many times real time
/// on the Neural Engine.
final class ParakeetChannel: AudioChanneling, @unchecked Sendable {
    let name: String
    private let emit: (String, String, Bool, Double?) -> Void
    private let onStatus: (String) -> Void

    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var samples: [Float] = []
    private var policy = ChunkPolicy()
    private var stopped = false
    private var chain: Task<Void, Never>?

    private var convertFailures = 0
    private var convertSuccesses = 0
    private var convertProblemReported = false

    /// Conversion failures used to return an empty block, which the
    /// caller drops without a word: a channel could eat every buffer
    /// for a whole call and look merely quiet. Count them, and say so
    /// once when nothing at all converts.
    private func noteConvertFailure() {
        convertFailures += 1
        if convertFailures >= 30, convertSuccesses == 0, !convertProblemReported {
            convertProblemReported = true
            onStatus("Audio from the \(name == "them" ? "other side" : "microphone") cannot be converted for transcription, so nothing will be heard from it.")
        }
    }

    init(name: String,
         emit: @escaping (String, String, Bool, Double?) -> Void, onStatus: @escaping (String) -> Void) {
        self.name = name
        self.emit = emit
        self.onStatus = onStatus
    }

    func start() {
        let onStatus = self.onStatus
        Task {
            do {
                try await ParakeetRuntime.shared.prepare()
                onStatus("Listening (Parakeet Ultra)")
            } catch {
                onStatus("Parakeet Ultra failed to load: \(error.localizedDescription). Check the network for the first download, or pick another engine in Settings, Speech.")
            }
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let tail = samples
        let hadSpeech = policy.hasSpeech
        samples = []
        policy.reset()
        lock.unlock()
        chain?.cancel()
        chain = nil
        if hadSpeech, tail.count >= ChunkPolicy.sampleRate / 2 {
            let name = self.name, emit = self.emit
            Task {
                if let text = try? await ParakeetRuntime.shared.transcribe(samples: tail), !text.isEmpty {
                    emit(name, text, true, Double(tail.count) / 16_000)
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let floats = convert(buffer)
        guard !floats.isEmpty else { return }
        let rms = WhisperChannel.rms(of: floats)
        lock.lock()
        if stopped { lock.unlock(); return }
        samples.append(contentsOf: floats)
        let ready = policy.feed(blockSamples: floats.count, rms: rms)
        var chunk: [Float]?
        if ready {
            if policy.hasSpeech {
                let keepSilence = Int(0.3 * Double(ChunkPolicy.sampleRate))
                let trim = min(policy.trailingSilentSamples - keepSilence, samples.count)
                chunk = Array(samples.dropLast(max(0, trim)))
            }
            samples = []
            policy.reset()
        }
        lock.unlock()
        if let chunk, chunk.count >= ChunkPolicy.sampleRate / 2 {
            enqueue(chunk)
        }
    }

    private func enqueue(_ chunk: [Float]) {
        let name = self.name, emit = self.emit
        let previous = chain
        chain = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            if let text = try? await ParakeetRuntime.shared.transcribe(samples: chunk), !text.isEmpty {
                emit(name, text, true, Double(chunk.count) / 16_000)
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else {
            noteConvertFailure()
            return []
        }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return [] }
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
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else {
            noteConvertFailure()
            return []
        }
        convertSuccesses += 1
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}

/// A PNG of the frontmost window that is not InterviewAI itself: the call
/// window or the coding problem in front of the user.
public enum ScreenCapturer {
    public static func frontWindowPNG(excludingBundleID: String) async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.windows.filter { window in
            window.isOnScreen
                && window.owningApplication?.bundleIdentifier != excludingBundleID
                && window.frame.width > 200 && window.frame.height > 200
        }
        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw BrainError.empty
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw BrainError.empty
        }
        return data
    }

    /// The whole main display as a JPEG, for the bug report screenshot.
    /// Downscaled to at most 1600 pixels wide so the report stays small
    /// enough to file with the issue.
    public static func displayJPEG() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw BrainError.empty }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let rep = NSBitmapImageRep(cgImage: image)
        let maxWidth = 1600
        if rep.pixelsWide > maxWidth {
            let ratio = Double(maxWidth) / Double(rep.pixelsWide)
            let target = NSSize(width: maxWidth, height: Int(Double(rep.pixelsHigh) * ratio))
            let scaled = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            scaled?.size = target
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled!)
            NSImage(cgImage: image, size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
                .draw(in: NSRect(origin: .zero, size: target))
            NSGraphicsContext.restoreGraphicsState()
            guard let data = scaled?.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                throw BrainError.empty
            }
            return data
        }
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw BrainError.empty
        }
        return data
    }
}

// MARK: - Speaker diarization (FluidAudio)

@globalActor
public actor DiarizationIsolation {
    public static let shared = DiarizationIsolation()
}

/// Who spoke when, on the other side's audio. FluidAudio's diarizer
/// (pyannote segmentation plus speaker embeddings) runs on this Mac;
/// the models download once into the same FluidAudio folder. The pass
/// is offline by design: it runs over the whole call when it ends, when
/// all the audio is there, and labels the saved transcript.
@DiarizationIsolation
public final class DiarizationRuntime {
    public nonisolated static let shared = DiarizationRuntime()
    nonisolated init() {}

    private var manager: DiarizerManager?

    public func prepare() async throws {
        if manager != nil { return }
        let models = try await DiarizerModels.load()
        let manager = DiarizerManager(config: .default)
        manager.initialize(models: models)
        self.manager = manager
    }

    /// Speaker ranges for a whole call's audio, 16 kHz mono. The pass
    /// itself is synchronous and heavy, so it holds this actor while it
    /// runs; nothing else queues behind it.
    public func diarize(samples: [Float]) async throws -> [SpeakerAssigner.Range] {
        try await prepare()
        guard let manager else { throw BrainError.empty }
        let result = try manager.performCompleteDiarization(samples)
        return result.segments.map {
            SpeakerAssigner.Range(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
    }
}
