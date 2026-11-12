import AVFoundation
import Foundation
import Testing
@testable import InterviewAIKit

private func makeBuffer(format: AVAudioFormat, frames: Int, value: (Int) -> Float) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    for channel in 0..<Int(format.channelCount) {
        let data = buffer.floatChannelData![channel]
        for frame in 0..<frames { data[frame] = value(frame) }
    }
    return buffer
}

@Test("Recorder writes both channels to a readable AAC file")
func recorderWritesBothChannels() async throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionAudioTests-\(UUID().uuidString)")
    let url = dir.appendingPathComponent("session.m4a")
    let recorder = SessionAudioRecorder(fileURL: url)
    #expect(recorder.start())
    #expect(recorder.isRecording)

    let themFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    let meFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    // Four quarter-second buffers per channel: one second of session.
    for _ in 0..<4 {
        recorder.appendThem(makeBuffer(format: themFormat, frames: 12_000) { frame in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(frame) / 48_000.0))
        })
        recorder.appendMe(makeBuffer(format: meFormat, frames: 12_000) { _ in 0.2 })
    }

    let ok = await withCheckedContinuation { continuation in
        recorder.stop { continuation.resume(returning: $0) }
    }
    #expect(ok)
    #expect(!recorder.isRecording)

    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    #expect(size > 1_000)

    let file = try AVAudioFile(forReading: url)
    #expect(file.fileFormat.channelCount == 2)
    #expect(file.fileFormat.sampleRate == 16_000)
    let capacity = AVAudioFrameCount(file.length)
    let readback = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity)!
    try file.read(into: readback)
    let count = Int(readback.frameLength)
    #expect(count > 12_000)
    #expect(count < 26_000)
    let left = readback.floatChannelData![0]
    let right = readback.floatChannelData![1]
    var leftEnergy = 0.0
    var rightSum = 0.0
    for frame in 0..<count {
        leftEnergy += abs(Double(left[frame]))
        rightSum += Double(right[frame])
    }
    // The other side's sine sits on the left, my steady tone on the right.
    #expect(leftEnergy / Double(count) > 0.1)
    #expect(abs(rightSum / Double(count) - 0.2) < 0.05)
    try? FileManager.default.removeItem(at: dir)
}

@Test("Recorder fails soft: bad path, stray appends, stop without start")
func recorderFailsSoft() async {
    let bad = SessionAudioRecorder(fileURL: URL(fileURLWithPath: "/nonexistent-dir-xyz/session.m4a"))
    #expect(!bad.start())
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    bad.appendMe(makeBuffer(format: format, frames: 4_800) { _ in 0.1 })
    let badStopped = await withCheckedContinuation { continuation in
        bad.stop { continuation.resume(returning: $0) }
    }
    #expect(!badStopped)

    let fresh = SessionAudioRecorder(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("never-started.m4a"))
    let freshStopped = await withCheckedContinuation { continuation in
        fresh.stop { continuation.resume(returning: $0) }
    }
    #expect(!freshStopped)
}

@Test("Store measures, finds and deletes audio files")
func storeHelpers() throws {
    let name = "store-test-\(UUID().uuidString).m4a"
    let url = SessionAudioStore.url(fileName: name)
    try Data(count: 2_048).write(to: url)
    #expect(SessionAudioStore.exists(fileName: name))
    #expect(SessionAudioStore.totalBytes() >= 2_048)
    SessionAudioStore.delete(fileName: name)
    #expect(!SessionAudioStore.exists(fileName: name))
    SessionAudioStore.delete(fileName: "")
    #expect(!SessionAudioStore.exists(fileName: ""))
}
