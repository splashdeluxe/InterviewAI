import Foundation
import Testing
@testable import InterviewAIKit

/// The bytes of a string, for building fixture headers.
private func bytes(_ string: String) -> [UInt8] {
    Array(string.utf8)
}

/// A realistic Ogg first page carrying an OpusHead packet, in
/// the shape a WhatsApp or Telegram voice note starts with:
/// capture pattern, version, header type, granule position,
/// serial, sequence, checksum, one segment of 19 bytes, then
/// the OpusHead packet itself (magic, version, channels,
/// pre-skip, sample rate, gain, mapping family).
private func oggOpusHeader() -> [UInt8] {
    var header = bytes("OggS")
    header += [0x00]                                // version
    header += [0x02]                                // header type: beginning of stream
    header += [UInt8](repeating: 0x00, count: 8)    // granule position
    header += [0x24, 0x08, 0x00, 0x00]              // serial number
    header += [0x00, 0x00, 0x00, 0x00]              // sequence number
    header += [0x00, 0x00, 0x00, 0x00]              // checksum
    header += [0x01]                                // segment count
    header += [0x13]                                // segment size: 19
    header += bytes("OpusHead")
    header += [0x01]                                // OpusHead version
    header += [0x02]                                // channels
    header += [0x38, 0x01]                          // pre-skip: 312
    header += [0x80, 0xBB, 0x00, 0x00]              // sample rate: 48000
    header += [0x00, 0x00]                          // gain
    header += [0x00]                                // mapping family
    return header
}

/// An Ogg first page whose first packet is the Vorbis
/// identification header: 0x01 followed by "vorbis".
private func oggVorbisHeader() -> [UInt8] {
    var header = bytes("OggS")
    header += [UInt8](repeating: 0x00, count: 23)   // rest of the page header
    header += [0x1E]                                // segment size: 30
    header += [0x01]
    header += bytes("vorbis")
    header += [0x00, 0x00, 0x00, 0x00]              // Vorbis version
    return header
}

@Test("An Ogg page carrying OpusHead detects as Ogg Opus")
func oggOpusDetection() {
    #expect(AudioFileKind.detect(header: oggOpusHeader()) == .oggOpus)
}

@Test("An Ogg page carrying the Vorbis id header detects as Ogg Vorbis")
func oggVorbisDetection() {
    #expect(AudioFileKind.detect(header: oggVorbisHeader()) == .oggVorbis)
}

@Test("An Ogg page with no codec header in the bytes given detects as plain Ogg audio")
func oggAudioDetection() {
    var header = bytes("OggS")
    header += [UInt8](repeating: 0xAB, count: 40)
    #expect(AudioFileKind.detect(header: header) == .oggAudio)
}

@Test("A RIFF/WAVE header detects as WAV")
func wavDetection() {
    var header = bytes("RIFF")
    header += [0x24, 0x00, 0x00, 0x00]              // chunk size
    header += bytes("WAVE")
    header += bytes("fmt ")
    #expect(AudioFileKind.detect(header: header) == .wav)
}

@Test("A RIFF header without WAVE is not WAV")
func riffWithoutWaveIsUnknown() {
    var header = bytes("RIFF")
    header += [0x24, 0x00, 0x00, 0x00]
    header += bytes("AVI ")
    #expect(AudioFileKind.detect(header: header) == .unknown)
}

@Test("An ID3 tag detects as MP3, and so does a bare frame sync")
func mp3Detection() {
    var tagged = bytes("ID3")
    tagged += [0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    #expect(AudioFileKind.detect(header: tagged) == .mp3)
    #expect(AudioFileKind.detect(header: [0xFF, 0xFB, 0x90, 0x00]) == .mp3)
}

@Test("The MP4 audio brands detect as M4A, the other brands as MP4 video")
func mp4FamilyDetection() {
    var audio = [UInt8](repeating: 0x00, count: 4)
    audio += bytes("ftyp")
    audio += bytes("M4A ")
    audio += [0x00, 0x00, 0x00, 0x00]
    #expect(AudioFileKind.detect(header: audio) == .m4a)

    var audiobook = [UInt8](repeating: 0x00, count: 4)
    audiobook += bytes("ftyp")
    audiobook += bytes("M4B ")
    #expect(AudioFileKind.detect(header: audiobook) == .m4a)

    var video = [UInt8](repeating: 0x00, count: 4)
    video += bytes("ftyp")
    video += bytes("isom")
    video += [0x00, 0x00, 0x02, 0x00]
    #expect(AudioFileKind.detect(header: video) == .mp4Video)

    var quickTime = [UInt8](repeating: 0x00, count: 4)
    quickTime += bytes("ftyp")
    quickTime += bytes("qt  ")
    #expect(AudioFileKind.detect(header: quickTime) == .mp4Video)
}

@Test("Short, empty and random headers detect as unknown")
func unknownDetection() {
    #expect(AudioFileKind.detect(header: []) == .unknown)
    #expect(AudioFileKind.detect(header: [0x00, 0x11]) == .unknown)
    #expect(AudioFileKind.detect(header: bytes("Og")) == .unknown)
    #expect(AudioFileKind.detect(header: [0x10, 0x22, 0x35, 0x47, 0x59, 0x6B, 0x7D, 0x8F]) == .unknown)
}

@Test("Extensions map to kinds, case-insensitively")
func extensionDetection() {
    #expect(AudioFileKind.detect(pathExtension: "ogg") == .oggAudio)
    #expect(AudioFileKind.detect(pathExtension: "oga") == .oggAudio)
    #expect(AudioFileKind.detect(pathExtension: "opus") == .oggOpus)
    #expect(AudioFileKind.detect(pathExtension: "wav") == .wav)
    #expect(AudioFileKind.detect(pathExtension: "mp3") == .mp3)
    #expect(AudioFileKind.detect(pathExtension: "m4a") == .m4a)
    #expect(AudioFileKind.detect(pathExtension: "mp4") == .mp4Video)
    #expect(AudioFileKind.detect(pathExtension: "m4v") == .mp4Video)
    #expect(AudioFileKind.detect(pathExtension: "mov") == .mp4Video)
    #expect(AudioFileKind.detect(pathExtension: "xyz") == .unknown)
    #expect(AudioFileKind.detect(pathExtension: "OGG") == .oggAudio)
    #expect(AudioFileKind.detect(pathExtension: "Opus") == .oggOpus)
    #expect(AudioFileKind.detect(pathExtension: "") == .unknown)
}

@Test("Only the Ogg kinds are Ogg family, and only they need the ffmpeg fallback")
func oggFamilyTruthTable() {
    let kinds: [AudioFileKind] = [.oggOpus, .oggVorbis, .oggAudio, .wav, .mp3, .m4a, .mp4Video, .unknown]
    for kind in kinds {
        let expected = kind == .oggOpus || kind == .oggVorbis || kind == .oggAudio
        #expect(kind.isOggFamily == expected)
        #expect(kind.needsFFmpegFallback == expected)
    }
    #expect(AudioFileKind.detect(header: oggOpusHeader()).isOggFamily)
    #expect(AudioFileKind.detect(header: oggOpusHeader()).needsFFmpegFallback)
}
