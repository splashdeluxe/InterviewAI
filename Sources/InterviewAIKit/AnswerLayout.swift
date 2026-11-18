import Foundation

/// How the Live page divides its width between the transcript and
/// the answer, picked from the menu in the Answer header (the shape
/// Hedy's chat view uses: Balanced, Chat Focus, Full Width). Pure
/// proportions, so the views only read numbers from here and the
/// choices are unit tested.
public enum AnswerLayout: String, CaseIterable, Sendable {
    case balanced
    case answerFocus
    case fullWidth

    public var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .answerFocus: return "Answer Focus"
        case .fullWidth: return "Full Width"
        }
    }

    /// The transcript's share of the split width. Full Width gives
    /// the answer everything and hides the transcript panel; it is
    /// still recorded, and the layout menu brings it back.
    public var transcriptFraction: Double {
        switch self {
        case .balanced: return 0.5
        case .answerFocus: return 0.32
        case .fullWidth: return 0
        }
    }

    public var showsTranscript: Bool { self != .fullWidth }
}
