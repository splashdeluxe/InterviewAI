import Foundation

/// Guesses what a context file is: a resume, a job description, notes,
/// or a general file. The name decides first. When the name says
/// nothing, the text decides: a person's own resume is usually named
/// after the person, so the name alone misses exactly the file that
/// matters most. The text rules need two or more markers and a clear
/// winner, so mixed documents (a prep pack that quotes both sides)
/// stay general.
public enum ContextClassifier {
    public static func kind(forName name: String, text: String = "") -> String {
        let fromName = kindFromName(name)
        if fromName != "general" { return fromName }
        return kindFromText(text) ?? "general"
    }

    public static func kindFromName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("resume") || lower.contains("cv") || lower.contains("lebenslauf") { return "resume" }
        if lower.contains("jd") || lower.contains("job") || lower.contains("position") || lower.contains("role") { return "job" }
        if lower.contains("note") { return "notes" }
        return "general"
    }

    static func kindFromText(_ text: String) -> String? {
        let lower = text.lowercased()
        guard lower.count > 200 else { return nil }
        let resumeMarkers = ["work experience", "professional experience", "employment history",
                             "education", "skills", "curriculum vitae", "career summary",
                             "professional summary", "certifications", "languages"]
        let jobMarkers = ["responsibilities", "requirements", "qualifications",
                          "what you will do", "what you'll do", "about the role",
                          "we are looking for", "equal opportunity", "apply now", "benefits"]
        let resumeScore = resumeMarkers.count { lower.contains($0) }
        let jobScore = jobMarkers.count { lower.contains($0) }
        if resumeScore >= 2, resumeScore > jobScore { return "resume" }
        if jobScore >= 2, jobScore > resumeScore { return "job" }
        return nil
    }
}
