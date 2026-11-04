import Foundation

/// Keyword ranking and prompt building. Plain, local, and explainable:
/// no embeddings, no server. Pinned files always go in whole. Other files
/// are scored against the question by shared words and cut to a budget.
public enum ContextRanker {
    public static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
    }

    /// How many question words appear in the document. 0 means no overlap.
    public static func score(document: String, query: String) -> Int {
        let queryWords = words(query)
        guard !queryWords.isEmpty else { return 0 }
        let documentWords = words(document)
        return queryWords.intersection(documentWords).count
    }

    /// Ranked documents for a query: pinned first (score ignored), then by
    /// score, dropping zero-score unpinned documents.
    public static func rank(documents: [(name: String, text: String, pinned: Bool)], query: String) -> [(name: String, text: String)] {
        let scored = documents.map { (doc: $0, score: score(document: $0.text, query: query)) }
        let pinned = scored.filter { $0.doc.pinned }
        let rest = scored.filter { !$0.doc.pinned && $0.score > 0 }.sorted { $0.score > $1.score }
        return (pinned + rest).map { (name: $0.doc.name, text: $0.doc.text) }
    }
}

public enum PromptBuilder {
    /// Word budget for context in one prompt, roughly 6,000 characters.
    public static let contextCharBudget = 24_000

    public static func systemPrompt(modePrompt: String) -> String {
        modePrompt + "\n\nRules: use only facts from the context and the conversation. If a fact is not there, do not invent it. Keep answers speakable and short unless I ask for detail."
    }

    /// The user message: context block, recent transcript, then the task.
    public static func userMessage(
        action: AnswerAction?,
        typedQuestion: String?,
        customContext: String,
        documents: [(name: String, text: String, pinned: Bool)],
        transcript: [TranscriptSegment],
        screenshotNote: Bool
    ) -> String {
        let question = typedQuestion ?? transcript.last(where: { $0.channel == "them" && $0.isFinal })?.text ?? ""
        var parts: [String] = []

        var contextBlocks: [String] = []
        if !customContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextBlocks.append("My notes for this call:\n\(customContext)")
        }
        var used = contextBlocks.joined().count
        for doc in ContextRanker.rank(documents: documents, query: question) {
            let block = "From \(doc.name):\n\(doc.text)"
            if used + block.count > contextCharBudget { continue }
            used += block.count
            contextBlocks.append(block)
        }
        if !contextBlocks.isEmpty {
            parts.append("Context:\n" + contextBlocks.joined(separator: "\n\n"))
        }

        let recent = transcript.filter(\.isFinal).suffix(40)
        if !recent.isEmpty {
            parts.append("Conversation so far:\n" + TranscriptSegment.plainText(Array(recent)))
        }

        var task = action?.instruction ?? "Answer the last question from the other side."
        if let typedQuestion, !typedQuestion.isEmpty {
            task += "\n\nMy question: \(typedQuestion)"
        }
        if screenshotNote {
            task += "\n\nA screenshot of my screen is attached. Use what it shows."
        }
        parts.append(task)
        return parts.joined(separator: "\n\n")
    }

    /// The end-of-meeting summary request. Written as plain directions,
    /// not a labelled template: a small local model echoes a template's
    /// labels back as its answer (see SummaryCleaner).
    public static func summaryMessage(transcript: [TranscriptSegment], notes: String) -> String {
        """
        Write the summary of this meeting, from the transcript and my notes below.

        Write only the summary itself. Start directly with the summary text. No title, no headings, no labels, and do not repeat any part of these instructions.

        Cover, in this order: what was discussed, in three to five lines; then the decisions, as a short bullet list; then the action items with owners where named, as a short bullet list. If there were no decisions or no action items, leave that part out.

        Then write a line with only ===, and after it a short follow-up message I can send, in my voice, thanking them and restating the next step.

        My notes:
        \(notes.isEmpty ? "(none)" : notes)

        Transcript:
        \(TranscriptSegment.plainText(transcript))
        """
    }
}

/// Small local models sometimes answer the summary request by echoing
/// its scaffolding ("### Shape: Summary: Summary: Decision: Action
/// item:") instead of writing a summary. This strips a leading
/// scaffolding block so it can never be stored as the summary. Only
/// the lead is touched: the first real content line and everything
/// after it are kept as written.
public enum SummaryCleaner {
    private static let labels = ["shape", "summary", "decision", "decisions",
                                 "action item", "action items",
                                 "follow-up", "follow up", "notes", "transcript"]

    public static func clean(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        while let first = lines.first {
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || isScaffoldLine(trimmed) {
                lines.removeFirst()
            } else {
                break
            }
        }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // One leading label on the first content line goes too:
        // "Summary: We agreed..." reads as "We agreed...".
        if text.lowercased().hasPrefix("summary:") {
            text = String(text.dropFirst("summary:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// A line made only of scaffolding labels and punctuation, like
    /// "Shape:" or "Summary: Summary: Decision: Action item:".
    static func isScaffoldLine(_ line: String) -> Bool {
        var rest = line.lowercased()
        for label in labels { rest = rest.replacingOccurrences(of: label, with: " ") }
        rest = rest.replacingOccurrences(of: ":", with: " ")
        return rest.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Translation of transcript lines through the user's own provider: the
/// local model by default, so a German call can be read in English (or
/// the other way round) while it happens. The prompt is deliberately
/// bare: translate only, invent nothing.
public enum TranslationPrompts {
    /// Target languages offered in Settings.
    public static let languages = ["English", "German", "Russian", "Indonesian", "Spanish"]

    public static func system(target: String) -> String {
        "You translate spoken interview lines into \(target). Output only the translation, nothing else: no quotes, no notes, no original text. Keep names, numbers, and technical terms exact. If the line is already in \(target), return it unchanged."
    }
}
