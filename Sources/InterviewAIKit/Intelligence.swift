import Foundation

/// Prompts for the Intelligence page: the layers that ground answers in
/// the user. Everything here is generated from the user's own files by
/// the user's own provider. No layer is gated, metered, or hosted.
public enum IntelligencePrompts {
    private static let honesty = "Use only facts stated in the documents below. Never invent employers, dates, numbers, skills, or results. Where something is missing, say so plainly in one line instead of filling the gap."

    public static func profile(resume: String) -> (system: String, user: String) {
        (system: "You extract a structured professional profile from a resume. \(honesty)",
         user: """
         Copy names, titles, companies, and years exactly as written.

         Write the profile in markdown, exactly these sections:
         ## Identity
         Name, current role, location line, one-sentence summary.
         ## Roles
         One bullet per role: title, company, years.
         ## Experience and education
         The work history in the resume's own order, one line per role
         with the years, then the education lines.
         ## Skills
         Bullets grouped by theme.
         ## Strongest evidence
         Up to five bullets with the hardest numbers in the resume.

         Resume:
         \(resume)
         """)
    }

    public static func talkingPoints(resume: String, jobDescription: String) -> (system: String, user: String) {
        (system: "You prepare interview talking points by matching a resume to a job description. \(honesty)",
         user: """
         Write in markdown, exactly these sections:
         ## Fit points
         Up to six bullets: the job requirement, then the matching resume
         evidence with the number or example that proves it, in first
         person ("I ...").
         ## Gaps, answered honestly
         Up to four bullets: the requirement with weak or no evidence, a
         plain admission, and the closest bridging experience. Never dress
         a gap up as a strength.
         ## Questions to ask them
         Three sharp questions about the role and team.

         Resume:
         \(resume)

         Job description:
         \(jobDescription)
         """)
    }

    public static func companyIntel(company: String, jobDescription: String, webResults: [SearchResult]) -> (system: String, user: String) {
        var web = "No web results were provided."
        if !webResults.isEmpty {
            web = webResults.map { "- \($0.title) (\($0.url))\n  \($0.snippet)" }.joined(separator: "\n")
        }
        return (system: "You write a short, factual company brief for interview preparation. \(honesty) Web snippets may be quoted as leads, marked as such, never as established facts.",
         user: """
         Company: \(company)

         Two to four lines per section. If the web leads and the job
         description disagree, trust the job description and mark the
         lead as unverified.

         Write in markdown, exactly these sections:
         ## What they do
         ## The role in their world
         ## Likely interview angles
         ## Smart questions

         Job description:
         \(jobDescription.isEmpty ? "(none provided)" : jobDescription)

         Web results (leads, unverified):
         \(web)
         """)
    }

    public static func coverLetter(resume: String, jobDescription: String) -> (system: String, user: String) {
        (system: "You draft a cover letter in the first person, plain and specific, no flattery and no filler. \(honesty)",
         user: """
         One page at most, ready to send. Open with the role and the
         strongest matching evidence, not with "I am writing to apply".
         Middle: two short paragraphs of evidence.
         Close: availability and a plain sign-off with the name from the
         resume. No placeholders in brackets.

         Resume:
         \(resume)

         Job description:
         \(jobDescription)
         """)
    }
}

/// One web result, from the user's own search key.
public struct SearchResult: Equatable, Sendable {
    public var title: String
    public var url: String
    public var snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

/// Live web search through Tavily, with the user's own key from the
/// Keychain. Off until a key exists; nothing is proxied or hosted.
public enum WebSearch {
    public static func tavily(query: String, apiKey: String, maxResults: Int = 5) async throws -> [SearchResult] {
        guard !apiKey.isEmpty else { return [] }
        guard let url = URL(string: "https://api.tavily.com/search") else { throw BrainError.badURL("tavily") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "api_key": apiKey,
            "query": query,
            "max_results": maxResults,
            "search_depth": "basic",
        ])
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BrainError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return parseTavily(data: data)
    }

    /// Pull title, url, and snippet out of a Tavily response. Split out
    /// so it can be unit tested without a network call.
    public static func parseTavily(data: Data) -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let title = item["title"] as? String, let url = item["url"] as? String else { return nil }
            let snippet = (item["content"] as? String ?? "").prefix(400)
            return SearchResult(title: title, url: url, snippet: String(snippet))
        }
    }
}
