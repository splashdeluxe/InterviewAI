import Foundation

/// The end-of-session check behind the "Started by mistake?"
/// prompt: a session that captured only a few words is more
/// likely a false start than a meeting, so the app asks
/// before it saves. Zero words never prompts: an empty
/// session already saves nothing.
public enum SessionEnd {
    /// Fewer captured words than this, the app asks first.
    public static let mistakeWordLimit = 20

    /// Every word in the session's final lines, both channels.
    public static func wordCount(_ segments: [TranscriptSegment]) -> Int {
        segments.reduce(0) { total, segment in
            total + segment.text.split(whereSeparator: { $0.isWhitespace }).count
        }
    }

    /// Whether a stopped session captured little enough to
    /// ask about. The limit itself does not prompt: a session
    /// with exactly `mistakeWordLimit` words saves as usual.
    public static func looksLikeMistake(wordCount: Int) -> Bool {
        wordCount > 0 && wordCount < mistakeWordLimit
    }
}
