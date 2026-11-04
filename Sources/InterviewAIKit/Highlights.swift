import Foundation

/// Splits an answer into runs the UI can style: the terms the model
/// bolded, and the figures (amounts, percents, plain numbers). Both
/// read as the keywords worth catching mid-sentence, so the app can
/// wash them in yellow when the Highlight Keywords setting is on.
/// Pure string work, no model call.
public enum AnswerHighlight {
    public enum Style: Equatable, Sendable {
        case plain
        case emphasis  // **bold** in the raw answer, markers stripped
        case figure    // €1.5, 42%, 2024, 3.5
    }

    public struct Run: Equatable, Sendable {
        public let text: String
        public let style: Style
        public init(text: String, style: Style) {
            self.text = text
            self.style = style
        }
    }

    private static let boldPattern = #"\*\*([^*]+)\*\*"#
    private static let figurePattern = #"[$€£]?\d[\d.,]*%?|\d+([.,]\d+)?\s?(percent|EUR|USD|GBP)"#

    public static func runs(in text: String) -> [Run] {
        var out: [Run] = []
        func append(_ piece: String, _ style: Style) {
            guard !piece.isEmpty else { return }
            if let last = out.last, last.style == style {
                out[out.count - 1] = Run(text: last.text + piece, style: style)
            } else {
                out.append(Run(text: piece, style: style))
            }
        }
        func appendPlainWithFigures(_ piece: String) {
            guard let regex = try? NSRegularExpression(pattern: figurePattern) else {
                append(piece, .plain)
                return
            }
            let ns = piece as NSString
            var cursor = 0
            for match in regex.matches(in: piece, range: NSRange(location: 0, length: ns.length)) {
                if match.range.location > cursor {
                    append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), .plain)
                }
                append(ns.substring(with: match.range), .figure)
                cursor = match.range.location + match.range.length
            }
            if cursor < ns.length {
                append(ns.substring(from: cursor), .plain)
            }
        }

        guard let bold = try? NSRegularExpression(pattern: boldPattern) else {
            appendPlainWithFigures(text)
            return out
        }
        let ns = text as NSString
        var cursor = 0
        for match in bold.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                appendPlainWithFigures(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            append(ns.substring(with: match.range(at: 1)), .emphasis)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            appendPlainWithFigures(ns.substring(from: cursor))
        }
        return out
    }
}
