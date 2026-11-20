import Foundation

/// What kind of audio (or video) file an import is holding,
/// worked out from the file's first bytes or, when no bytes are
/// at hand, from its name's extension. Meeting import asks this
/// before it hands a file to AVFoundation: the Ogg family —
/// WhatsApp and Telegram voice notes above all — is the one
/// AVFoundation may not open on older macOS, so those files take
/// the ffmpeg fallback instead of failing as unreadable. This
/// file only sniffs; it never opens or decodes anything.
public enum AudioFileKind: String, Sendable {
    /// An Ogg container carrying Opus: the shape of a WhatsApp
    /// or Telegram voice note.
    case oggOpus
    /// An Ogg container carrying Vorbis.
    case oggVorbis
    /// An Ogg container whose codec the given header bytes do
    /// not identify — either the codec's own header sits past
    /// the bytes given, or it is a codec this sniffer does not
    /// name. Still Ogg family for handling purposes.
    case oggAudio
    /// A WAV file.
    case wav
    /// An MP3 file, with an ID3 tag or straight at a frame.
    case mp3
    /// An MP4-family file whose brand says audio only: M4A
    /// or M4B.
    case m4a
    /// Any other MP4-family file: a video, or a container
    /// import should treat as one.
    case mp4Video
    /// Nothing matched, or there were not enough bytes to
    /// be sure.
    case unknown

    /// The kind a file's opening bytes say it is. Only the
    /// bytes given are looked at, so a caller can pass the
    /// first chunk of a file without reading the whole thing.
    /// Short or empty input is fine: when there are not enough
    /// bytes to be sure of a kind, the answer is `.unknown`.
    public static func detect(header: [UInt8]) -> AudioFileKind {
        if has(Array("OggS".utf8), at: 0, in: header) {
            if contains(Array("OpusHead".utf8), in: header) {
                return .oggOpus
            }
            if contains([0x01] + Array("vorbis".utf8), in: header) {
                return .oggVorbis
            }
            return .oggAudio
        }
        if has(Array("RIFF".utf8), at: 0, in: header),
           has(Array("WAVE".utf8), at: 8, in: header) {
            return .wav
        }
        if has(Array("ID3".utf8), at: 0, in: header) {
            return .mp3
        }
        if header.count >= 2, header[0] == 0xFF, (header[1] & 0xE0) == 0xE0 {
            return .mp3
        }
        if has(Array("ftyp".utf8), at: 4, in: header) {
            // The brand sits at bytes 8-11. A header too short
            // to carry one is still certainly MP4 family, so it
            // lands on the family's default, video.
            if has(Array("M4A ".utf8), at: 8, in: header)
                || has(Array("M4B ".utf8), at: 8, in: header) {
                return .m4a
            }
            return .mp4Video
        }
        return .unknown
    }

    /// The kind a file extension claims, for when import has a
    /// name before it has bytes. Case-insensitive, and a leading
    /// dot is ignored. An Ogg name cannot say which codec is
    /// inside, so "ogg" and "oga" answer `.oggAudio`; only the
    /// "opus" name answers `.oggOpus`. Anything unlisted is
    /// `.unknown`.
    public static func detect(pathExtension ext: String) -> AudioFileKind {
        var name = ext.lowercased()
        if name.hasPrefix(".") {
            name.removeFirst()
        }
        switch name {
        case "ogg", "oga": return .oggAudio
        case "opus": return .oggOpus
        case "wav": return .wav
        case "mp3": return .mp3
        case "m4a": return .m4a
        case "mp4", "m4v", "mov": return .mp4Video
        default: return .unknown
        }
    }

    /// Whether this kind is one of the Ogg container kinds,
    /// whatever codec rides inside.
    public var isOggFamily: Bool {
        switch self {
        case .oggOpus, .oggVorbis, .oggAudio: return true
        case .wav, .mp3, .m4a, .mp4Video, .unknown: return false
        }
    }

    /// Whether import should plan on decoding this file with
    /// the ffmpeg fallback rather than AVFoundation. Today that
    /// is exactly the Ogg family: the kinds AVFoundation may
    /// not open on older macOS.
    public var needsFFmpegFallback: Bool {
        isOggFamily
    }

    /// Whether `bytes` holds `expected` starting at `offset`,
    /// with enough bytes present to tell.
    private static func has(_ expected: [UInt8], at offset: Int, in bytes: [UInt8]) -> Bool {
        guard offset >= 0, bytes.count >= offset + expected.count else { return false }
        return Array(bytes[offset..<(offset + expected.count)]) == expected
    }

    /// Whether `needle` appears anywhere in `haystack`. The
    /// codec headers this looks for sit inside the first Ogg
    /// page, not at a fixed offset, so they are scanned for
    /// rather than read at a position.
    private static func contains(_ needle: [UInt8], in haystack: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}
