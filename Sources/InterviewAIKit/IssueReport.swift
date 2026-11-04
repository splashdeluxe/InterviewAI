import Foundation

/// Builds the GitHub issue for a report written in the app. Pure text
/// work, so it is unit tested. The app sends the report to a small
/// relay that files the issue; the web page form is the fallback.
public enum IssueReport {
    public static let repoPath = "splashdeluxe/InterviewAI"

    /// The first line of the report, capped at 80 characters. A blank
    /// report gets a plain fallback title.
    public static func title(_ text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Issue in InterviewAI" }
        return String(trimmed.prefix(80))
    }

    public static func body(description: String, version: String, macOS: String, engine: String) -> String {
        """
        \(description.trimmingCharacters(in: .whitespacesAndNewlines))

        ---
        Filed from InterviewAI \(version) on macOS \(macOS). Transcription engine: \(engine).
        """
    }

    /// The same issue as a prefilled web page, for when no token is
    /// stored and the API cannot file it directly.
    public static func webURL(description: String, version: String, macOS: String, engine: String) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repoPath)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title(description)),
            URLQueryItem(name: "body", value: body(description: description, version: version, macOS: macOS, engine: engine)),
        ]
        return components?.url
    }
}
