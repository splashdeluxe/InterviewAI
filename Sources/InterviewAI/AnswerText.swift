import SwiftUI
import InterviewAIKit

/// The answer readout. Renders the model's bold terms semibold and,
/// when Highlight Keywords is on, washes the bold terms and the
/// figures (amounts, percents, numbers) in yellow so the point lands
/// at a glance. The size follows the Font Size setting.
struct AnswerTextView: View {
    let text: String
    @AppStorage("reading.highlightKeywords") private var highlightKeywords = true
    @AppStorage("reading.answerFontSize") private var answerFontSize = 14.0

    var body: some View {
        Text(rendered)
            .font(.system(size: answerFontSize))
            .textSelection(.enabled)
    }

    private var rendered: AttributedString {
        var out = AttributedString()
        for run in AnswerHighlight.runs(in: text) {
            var piece = AttributedString(run.text)
            switch run.style {
            case .plain:
                break
            case .emphasis:
                piece.font = .system(size: answerFontSize).weight(.semibold)
                if highlightKeywords { piece.backgroundColor = Color.yellow.opacity(0.45) }
            case .figure:
                if highlightKeywords { piece.backgroundColor = Color.yellow.opacity(0.45) }
            }
            out += piece
        }
        return out
    }
}
