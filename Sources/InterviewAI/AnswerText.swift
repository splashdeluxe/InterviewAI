import SwiftUI
import InterviewAIKit

/// The answer readout, built for a glance mid-call: the answer
/// arrives shaped one point per line, and this view gives each
/// line its own row. The first line (the direct answer) sits
/// larger and semibold; the points below stay at the set size in
/// secondary ink. The model's bold terms render semibold and,
/// when Highlight Keywords is on, the bold terms in the points
/// and the figures (amounts, percents, numbers) wash in wasabi;
/// the lead gets no wash, its size and weight already mark it. While the answer
/// streams, the line still being written stays dim, so the eye
/// rests on the finished lines and nothing jumps around. The
/// base size follows the Font Size setting.
struct AnswerTextView: View {
    let text: String
    var streaming: Bool = false
    @AppStorage("reading.highlightKeywords") private var highlightKeywords = true
    @AppStorage("reading.answerFontSize") private var answerFontSize = 14.0

    var body: some View {
        let lines = AnswerLines.lines(in: text)
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(runs(for: line, lead: index == 0))
                    .font(.system(size: index == 0 ? answerFontSize + 4 : answerFontSize,
                                  weight: index == 0 ? .semibold : .regular))
                    .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineSpacing(4)
                    .opacity(streaming && index == lines.count - 1 ? 0.55 : 1)
                    .textSelection(.enabled)
            }
        }
    }

    private func runs(for line: String, lead: Bool) -> AttributedString {
        let size = lead ? answerFontSize + 4 : answerFontSize
        var out = AttributedString()
        for run in AnswerHighlight.runs(in: line) {
            var piece = AttributedString(run.text)
            switch run.style {
            case .plain:
                break
            case .emphasis:
                piece.font = .system(size: size).weight(.semibold)
                // The lead line is already larger and semibold, so a
                // wash over a fully bolded lead would paint the whole
                // sentence. The wash marks terms in the points below.
                if highlightKeywords && !lead { piece.backgroundColor = Color(hex: 0xE9F056).opacity(0.45) }
            case .figure:
                if highlightKeywords { piece.backgroundColor = Color(hex: 0xE9F056).opacity(0.45) }
            }
            out += piece
        }
        return out
    }
}
