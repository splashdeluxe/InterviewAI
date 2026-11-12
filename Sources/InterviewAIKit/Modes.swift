import Foundation

/// A mode: a name, the system prompt that steers answers, and a notes
/// template. The nine built-in modes are original short prompts written
/// for InterviewAI. Users can add their own in the app.
public struct ModeDefinition: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    public var notesTemplate: String

    public init(id: String, name: String, prompt: String, notesTemplate: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.notesTemplate = notesTemplate
    }
}

public enum BuiltInModes {
    public static let general = ModeDefinition(
        id: "general", name: "General",
        prompt: "You help me in a meeting. Answers are short, concrete, and in first person where I would speak them. No filler, no hedging.",
        notesTemplate: "Decisions\n-\n\nOpen points\n-\n")

    public static let all: [ModeDefinition] = [
        general,
        ModeDefinition(
            id: "technical-interview", name: "Technical Interview",
            prompt: "You help me in a technical interview. For coding questions: state the approach first, then the key steps, then complexity. For system design: components, data flow, trade-offs. Keep it speakable.",
            notesTemplate: "Problem\n\nApproach\n\nComplexity\n"),
        ModeDefinition(
            id: "looking-for-work", name: "Looking for Work",
            prompt: "You help me in a job interview. Ground every answer in my resume and the job description in the context. Use my real numbers and examples. If the context does not cover a claim, keep the answer general and true. First person, confident, no bragging.",
            notesTemplate: "Role\n\nQuestions asked\n\nMy best answers\n\nFollow-ups I owe\n"),
        ModeDefinition(
            id: "behavioral", name: "Behavioral Interview",
            prompt: "You help me answer behavioural questions with the STAR shape: situation in one line, task in one line, action with my real work, result with a number where I have one. First person, under a minute spoken.",
            notesTemplate: "Question\n\nSituation\nTask\nAction\nResult\n"),
        ModeDefinition(
            id: "negotiation", name: "Negotiation",
            prompt: "You coach me through a negotiation live. Track every number mentioned. Suggest my next line, word for word, plus the reason behind it in one short line. Never advise me to invent a competing offer or a number I do not have.",
            notesTemplate: "Their numbers\n\nMy numbers\n\nAgreed\n"),
        ModeDefinition(
            id: "sales", name: "Sales",
            prompt: "You help me on a sales call. Suggest discovery questions, short answers to objections grounded in the context files, and a clear next step at the end.",
            notesTemplate: "Customer problem\n\nObjections\n\nNext step\n"),
        ModeDefinition(
            id: "recruiting", name: "Recruiting",
            prompt: "You help me interview a candidate. Suggest follow-up questions that test the claim just made, and keep a factual running summary of evidence for and against.",
            notesTemplate: "Candidate claims\n\nEvidence\n\nGaps to test\n"),
        ModeDefinition(
            id: "team-meet", name: "Team Meet",
            prompt: "You help me in a team meeting. Keep answers brief. Track decisions and action items as they happen and recap them on request.",
            notesTemplate: "Decisions\n\nAction items\n- [ ] \n"),
        ModeDefinition(
            id: "lecture", name: "Lecture",
            prompt: "You help me follow a lecture or talk. Explain new terms in one line, summarise each section, and list questions worth asking at the end.",
            notesTemplate: "Sections\n\nTerms\n\nQuestions\n"),
    ]

    public static func mode(id: String) -> ModeDefinition {
        all.first { $0.id == id } ?? general
    }
}

/// The section titles inside a mode's notes template. A template is
/// plain text: a heading line, an optional placeholder bullet, a
/// blank line, then the next heading. The titles are what the
/// Modes page lists as the mode's note sections, the same way
/// Metaview lists a template's sections. Placeholder bullets and
/// blank lines are not sections.
public enum ModeSections {
    public static func titles(from template: String) -> [String] {
        template.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("-") { return nil }
            return line
        }
    }
}
