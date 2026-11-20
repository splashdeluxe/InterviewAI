import Foundation

/// The user's own standing instructions for the drafts this app
/// writes after a call, set in Settings under "Writing
/// Instructions": tone, length, and format preferences, written
/// once and applied to every summary and scorecard afterwards.
/// This is the personal-instructions idea from Ashby's notetaker,
/// where a person's own instructions steer the drafts and win
/// over the company-wide ones; here there is only the person.
///
/// The scope is deliberate: instructions steer drafts, never
/// records. The transcript, its cleaned copy, and the found
/// questions are quotes and stay untouched, and live answers
/// during a call are not steered either. Every prompt that takes
/// the suffix also states that the facts and the required
/// structure outrank it, so an instruction can change how a
/// summary reads, never what it says happened.
enum WritingInstructions {
    static let defaultsKey = "generation.instructions"

    static var current: String {
        (UserDefaults.standard.string(forKey: defaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The paragraph appended to a draft prompt, empty when the
    /// user has written nothing.
    static var promptSuffix: String {
        let text = current
        guard !text.isEmpty else { return "" }
        return "\n\nThe user has written standing instructions for drafts like this one. Follow them for tone, length, and format, wherever they do not conflict with the facts in the transcript or the structure the task requires:\n\(text)"
    }
}
