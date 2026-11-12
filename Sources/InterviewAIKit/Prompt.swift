import Foundation

/// Keyword ranking and prompt building. Plain, local, and explainable:
/// no embeddings, no server. Pinned files go in first. Other files are
/// scored against the question by shared words. The whole context is
/// cut to a character budget, at word boundaries.
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

    public static func systemPrompt(modePrompt: String, answerLanguage: String? = nil) -> String {
        var prompt = modePrompt + "\n\nRules: Use only facts from the context and the conversation. If a fact is not there, do not invent it. Answer as me, in first person, ready to say out loud: no introduction, no explanation of the answer, no offer to help. Keep it short and speakable unless I ask for detail."
        if let answerLanguage, !answerLanguage.isEmpty {
            // The context and the profile are usually in the user's
            // language, the call in the other side's. Without this rule
            // a small model answers in whichever language the context
            // is written in, not the language of the conversation.
            prompt += "\n\nAnswer language: write every answer in \(answerLanguage). The documents and my notes may be in another language; that changes nothing. Names, figures, and quoted facts stay exactly as they are."
        }
        return prompt
    }

    /// The user message: context block, recent transcript, then the task.
    public static func userMessage(
        action: AnswerAction?,
        typedQuestion: String?,
        customContext: String,
        documents: [(name: String, text: String, pinned: Bool)],
        transcript: [TranscriptSegment],
        screenshotNote: Bool,
        answerLanguage: String? = nil
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
            let remaining = contextCharBudget - used
            if block.count <= remaining {
                used += block.count
                contextBlocks.append(block)
            } else if remaining >= 400 {
                // A file too big for what is left still lands, cut at a
                // word boundary. The old behaviour skipped it whole, so
                // a large pinned file silently never reached the model.
                let cut = truncateAtWord(block, limit: remaining)
                used += cut.count
                contextBlocks.append(cut)
            }
        }
        if !contextBlocks.isEmpty {
            parts.append("Context:\n" + contextBlocks.joined(separator: "\n\n"))
        }

        let recent = transcript.filter(\.isFinal).suffix(40)
        if !recent.isEmpty {
            parts.append("Conversation so far:\n" + TranscriptSegment.plainText(Array(recent)))
        }

        var task = action?.instruction ?? "Answer the last question from the other side directly, as me, in first person, ready to say out loud."
        if let typedQuestion, !typedQuestion.isEmpty {
            task += "\n\nMy question: \(typedQuestion)"
        } else if action != nil, !question.isEmpty {
            // Restate the target line right at the instruction. A
            // small model answers the line it was just shown far more
            // reliably than one it must dig out of the transcript.
            task += "\n\nThe other side just said: \"\(question)\""
        }
        if screenshotNote {
            task += "\n\nA screenshot of my screen is attached. Use what it shows, including any text or code on it."
        }
        if let answerLanguage, !answerLanguage.isEmpty {
            // Restated at the very end, where a small model weights an
            // instruction most: the system rule alone was not enough.
            task += "\n\nWrite the answer in \(answerLanguage)."
        }
        parts.append(task)
        return parts.joined(separator: "\n\n")
    }

    /// Cut a block to at most `limit` characters, ending at a word
    /// boundary, with a short marker so the model knows the file
    /// continues beyond what it can see.
    public static func truncateAtWord(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let marker = "\n[Cut here to fit this prompt. The file continues.]"
        let keep = limit - marker.count
        guard keep > 0 else { return String(text.prefix(limit)) }
        var slice = String(text.prefix(keep))
        if let lastSpace = slice.lastIndex(of: " ") {
            slice = String(slice[..<lastSpace])
        }
        return slice + marker
    }

    /// The end-of-meeting summary request. The shape is markdown with
    /// real headings: the Summary tab renders them (DocTextView), and
    /// a concrete structure is what makes the notes worth reading. The
    /// old request forbade headings and capped the whole thing at a
    /// few lines, which produced a thin paragraph that said nothing.
    /// SummaryCleaner strips an echoed scaffold if the model parrots
    /// the instructions instead of following them.
    public static func summaryMessage(transcript: [TranscriptSegment], notes: String, title: String = "", attendees: [String] = [], singleChannel: Bool = false) -> String {
        var opening = "Write the meeting notes from the transcript and my notes below."
        if !title.isEmpty {
            // The title is the calendar's label for the time slot (or a
            // line the user typed at setup), not a description of the
            // call that actually happened. A wrong label framed as
            // fact once turned a coaching call into birthday notes, so
            // the label is handed over as a hint that the transcript
            // outranks, never as the meeting's subject.
            opening += "\n\nContext, as a hint only: the calendar slot for this time was called \"\(title)\""
            if !attendees.isEmpty {
                opening += ", and the people invited were: \(attendees.joined(separator: ", "))"
            }
            opening += ". A booked appointment is often not the call that actually happened. If the transcript covers something else, write about the transcript and ignore the label completely: never call the meeting a birthday, a celebration, or anything else the transcript itself does not support."
        }
        if singleChannel {
            // Only the mic side was captured (the call ran on another
            // device). Speaker attribution is impossible, so the notes
            // must not pretend otherwise.
            opening += "\n\nOnly my side of this call was captured; the other side's voice was not recorded on its own channel, so some of my lines answer things you cannot hear. Do not attribute statements to any other named person, do not invent the other side's words or positions, and write the notes about the topics I discussed. Where the other side clearly took part, name the topic, not their words."
        }
        return opening + "\n\n" + """
        Use only facts from the transcript and my notes. Keep every name, number, date, and figure exactly as said. Never invent a decision, a deadline, or an owner. If something was discussed but not settled, it belongs under Open questions, not Decisions.

        The transcript labels the other side as "Them" and me as "Me". Keep who said what straight: never credit me with their words or them with mine, and never swap roles. A person's role counts only as the transcript or the attendee list states it.

        Write the notes in markdown, with exactly these sections, in this order:

        ## Overview
        What the meeting was about and how it ended, in three to five full sentences. Name the topics and the outcome, not just that a discussion happened.

        ## Key points
        The concrete facts worth remembering: up to seven bullets, one fact per bullet, with the figures and names as said. Skip small talk.

        ## Decisions
        Only decisions actually made, one bullet each. Leave this section out entirely if nothing was decided.

        ## Action items
        One bullet per task, written as: task, owner in brackets if a person was named, deadline if one was named. An agreed next step or timeline belongs here or in the Overview; never report one as missing when it was named. Leave this section out entirely if there are no tasks.

        ## Open questions
        Anything raised and left unanswered or undecided, one bullet each. Leave this section out entirely if there are none.

        Write only the notes. Start directly with "## Overview". Do not repeat any part of these instructions.

        Then write a line with only ===, and after it a short follow-up message I can send, in my voice, thanking them and restating the next step. Name the concrete next step and timing if they were agreed; if none was agreed, propose one politely. Address it only to a person the transcript itself names or hears; never address it to someone who appears only in the calendar label. If the transcript names nobody, keep the greeting general.

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
            // Markdown headings are content now: the notes are written
            // with ## sections and the Summary tab renders them. Only
            // blank lead lines and echoed scaffold go.
            if trimmed.isEmpty || isScaffoldLine(trimmed) {
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
    /// "Shape:" or "Summary: Summary: Decision: Action item:". Leading
    /// markdown marks are ignored, so "### Shape:" counts too, while a
    /// real heading like "## Overview" does not.
    static func isScaffoldLine(_ line: String) -> Bool {
        var rest = String(line.lowercased().drop(while: { $0 == "#" || $0 == " " }))
        for label in labels { rest = rest.replacingOccurrences(of: label, with: " ") }
        rest = rest.replacingOccurrences(of: ":", with: " ")
        rest = rest.replacingOccurrences(of: "-", with: " ")
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
        "You translate spoken interview lines into \(target). Output only the translation: no quotes, no notes, no original text. Keep names, numbers, and technical terms exact, and keep the speaker's tone and tense. If the line is already in \(target), return it unchanged."
    }
}
