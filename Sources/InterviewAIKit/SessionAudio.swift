import AudioToolbox
import AVFoundation
import Foundation

/// Where a session's saved audio lives: one AAC file per meeting in
/// the app's own support folder, named by the meeting's file name.
/// Files are deleted with their meeting; nothing leaves the Mac.
public enum SessionAudioStore {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("InterviewAI/Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func url(fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public static func exists(fileName: String) -> Bool {
        !fileName.isEmpty && FileManager.default.fileExists(atPath: url(fileName: fileName).path)
    }

    public static func delete(fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(fileName: fileName))
    }

    public static func totalBytes() -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.reduce(Int64(0)) { total, file in
            let size = (try? file.resourceValues(forKeys: Set(keys)).fileSize) ?? nil
            return total + Int64(size ?? 0)
        }
    }

    public static func formattedTotal() -> String {
        ByteCountFormatter.string(fromByteCount: totalBytes(), countStyle: .file)
    }
}

/// Records a live session's two channels to one AAC file: the other
/// side on the left, the microphone on the right, 16 kHz. The capture
/// path only converts and enqueues; the file work happens on its own
/// queue, and every failure lands as a flag, never as a throw, so a
/// broken recording can never take transcription down with it.
///
/// Both taps keep delivering while a call runs (silence included), so
/// pairing the channels by sample count keeps them in step. On stop,
/// the shorter side is padded with silence and everything is flushed.
public final class SessionAudioRecorder: @unchecked Sendable {
    public let fileURL: URL

    private let queue = DispatchQueue(label: "InterviewAI.SessionAudioRecorder")
    /// Guards the caller-thread state: the accept flag and the two
    /// sample converters. File state lives only on the queue.
    private let lock = NSLock()
    private var accepting = false
    private var converters: [String: AVAudioConverter] = [:]
    private var converterInputs: [String: AVAudioFormat] = [:]

    private var file: ExtAudioFileRef?
    private var failed = false
    /// Why the recording failed, in one short line, set at the first
    /// failure point and read by the session when it reports the
    /// failure. The recorder is fail-soft by design, so without this
    /// the failure is silent: the first version failed on real
    /// sessions while its unit tests passed, with nothing anywhere
    /// saying where it broke.
    public private(set) var failureSummary = ""
    private var firstFailure = ""
    /// Caller-thread counters, guarded by the lock: appends seen and
    /// sample frames successfully converted, per channel.
    private var appendsThem = 0
    private var appendsMe = 0
    private var convertedThem = 0
    private var convertedMe = 0
    private var pendingThem: [Float] = []
    private var pendingMe: [Float] = []
    /// Frames actually written to the file. Zero at stop means capture
    /// never delivered anything, which is a failure, not an empty
    /// recording worth keeping.
    private var wroteFrames = 0

    private let monoTarget = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let stereoTarget = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: true)!

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var isRecording: Bool {
        queue.sync { file != nil && !failed }
    }

    /// Queue only. Marks the recording failed and remembers the
    /// first reason; later failures do not overwrite it.
    private func markFailed(_ reason: String) {
        failed = true
        if firstFailure.isEmpty { firstFailure = reason }
    }

    /// Create the file and start accepting samples. Returns false when
    /// the file cannot be created; appends are then ignored.
    @discardableResult
    public func start() -> Bool {
        let created: Bool = queue.sync {
            if file != nil { return !failed }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var fileDescription = AudioStreamBasicDescription(
                mSampleRate: 16_000, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
                mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
                mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
            var ref: ExtAudioFileRef?
            guard ExtAudioFileCreateWithURL(
                fileURL as CFURL, kAudioFileM4AType, &fileDescription, nil,
                AudioFileFlags.eraseFile.rawValue, &ref) == noErr, let ref else {
                markFailed("the audio file could not be created")
                return false
            }
            var clientDescription = AudioStreamBasicDescription(
                mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
            guard ExtAudioFileSetProperty(
                ref, kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientDescription) == noErr else {
                ExtAudioFileDispose(ref)
                markFailed("the audio file format was refused")
                return false
            }
            file = ref
            return true
        }
        if created {
            lock.lock()
            accepting = true
            lock.unlock()
        }
        return created
    }

    public func appendThem(_ buffer: AVAudioPCMBuffer) { append(buffer, channel: "them") }
    public func appendMe(_ buffer: AVAudioPCMBuffer) { append(buffer, channel: "me") }

    private func append(_ buffer: AVAudioPCMBuffer, channel: String) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        if channel == "them" { appendsThem += 1 } else { appendsMe += 1 }
        let floats = convertLocked(buffer, channel: channel)
        if let floats {
            if channel == "them" { convertedThem += floats.count } else { convertedMe += floats.count }
        }
        lock.unlock()
        guard let floats, !floats.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, self.file != nil, !self.failed else { return }
            if channel == "them" { self.pendingThem.append(contentsOf: floats) }
            else { self.pendingMe.append(contentsOf: floats) }
            self.pumpAvailable()
        }
    }

    /// Same conversion shape as ThemCollector: whatever the tap hands
    /// over becomes 16 kHz mono floats. Called under the lock, because
    /// the two channels append from different threads.
    private func convertLocked(_ buffer: AVAudioPCMBuffer, channel: String) -> [Float]? {
        if converters[channel] == nil || converterInputs[channel] != buffer.format {
            converters[channel] = AVAudioConverter(from: buffer.format, to: monoTarget)
            converterInputs[channel] = buffer.format
        }
        guard let converter = converters[channel] else { return nil }
        let ratio = monoTarget.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: monoTarget, frameCapacity: capacity) else { return nil }
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
        guard status != .error, out.frameLength > 0, let samples = out.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: samples, count: Int(out.frameLength)))
    }

    /// Queue only. Writes pending samples as interleaved stereo: them
    /// on the left, me on the right, the shorter side padded with
    /// silence. Writes happen in bounded chunks, never in one giant
    /// buffer: the first version paired only when both sides had
    /// samples and flushed everything at stop, so a call whose other
    /// side never reached this Mac (a phone call next to it) buffered
    /// the whole session in memory and failed on the final write,
    /// deleting a recording that should have been kept.
    private func writeFrames(_ count: Int) {
        guard let file, !failed, count > 0,
              let out = AVAudioPCMBuffer(pcmFormat: stereoTarget, frameCapacity: AVAudioFrameCount(count)),
              let data = out.floatChannelData?[0] else {
            markFailed("a write buffer could not be made")
            return
        }
        out.frameLength = AVAudioFrameCount(count)
        for index in 0..<count {
            data[index * 2] = index < pendingThem.count ? pendingThem[index] : 0
            data[index * 2 + 1] = index < pendingMe.count ? pendingMe[index] : 0
        }
        pendingThem.removeFirst(min(count, pendingThem.count))
        pendingMe.removeFirst(min(count, pendingMe.count))
        if ExtAudioFileWrite(file, UInt32(count), out.mutableAudioBufferList) != noErr {
            markFailed("writing the audio file failed")
        } else {
            wroteFrames += count
        }
    }

    /// Write what can be written now: paired chunks while both sides
    /// have samples, and any one-sided excess beyond a second, so a
    /// silent channel never holds the other side's audio hostage in
    /// memory for the whole session.
    private func pumpAvailable() {
        while min(pendingThem.count, pendingMe.count) >= 4096 {
            writeFrames(4096)
            if failed { return }
        }
        let excess = pendingThem.count - pendingMe.count
        if abs(excess) > 16_000 {
            writeFrames(abs(excess) - 8_192)
        }
    }

    /// Flush everything left at stop, in bounded chunks.
    private func pumpFinal() {
        while !pendingThem.isEmpty || !pendingMe.isEmpty {
            writeFrames(min(16_384, max(pendingThem.count, pendingMe.count)))
            if failed { return }
        }
    }

    /// Flush, close, and report. The completion runs on the recorder's
    /// queue; true means a non-empty file is on disk at fileURL. A
    /// failed recording deletes its partial file, so a meeting never
    /// points at audio that is not really there.
    public func stop(completion: @escaping (Bool) -> Void) {
        lock.lock()
        accepting = false
        lock.unlock()
        let box = CompletionBox(completion)
        queue.async { [weak self] in
            guard let self else { box.completion(false); return }
            guard self.file != nil else { box.completion(false); return }
            if !self.failed { self.pumpFinal() }
            let ref = self.file
            self.file = nil
            if let ref { ExtAudioFileDispose(ref) }
            var ok = !self.failed && self.wroteFrames > 0
            if ok {
                let size = (try? FileManager.default.attributesOfItem(atPath: self.fileURL.path))?[.size] as? NSNumber
                ok = (size?.int64Value ?? 0) > 0
                if !ok { self.markFailed("the finished file was empty") }
            }
            if !ok {
                self.lock.lock()
                let counts = "them \(self.appendsThem) appends, \(self.convertedThem) frames; me \(self.appendsMe) appends, \(self.convertedMe) frames; wrote \(self.wroteFrames)"
                self.lock.unlock()
                self.failureSummary = self.firstFailure.isEmpty
                    ? "nothing was written (\(counts))"
                    : "\(self.firstFailure) (\(counts))"
                try? FileManager.default.removeItem(at: self.fileURL)
            }
            box.completion(ok)
        }
    }
}

/// Carries a stop completion across the recorder's queue without
/// tripping the strict-concurrency checks on the Kit target.
private final class CompletionBox: @unchecked Sendable {
    let completion: (Bool) -> Void
    init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }
}
