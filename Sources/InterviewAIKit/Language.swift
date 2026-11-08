import Foundation
import NaturalLanguage

/// Which language answers are written in. Two ways to get one: the
/// user pins a language in Settings, or the app matches the other
/// side. Matching reads the language of what the other side actually
/// said, on device, with no extra model call: NaturalLanguage names
/// the dominant language of the recent "them" lines, and that name
/// goes into the answer prompt.
public enum AnswerLanguage {
    /// Languages offered as a fixed choice in Settings.
    public static let languages = ["English", "German", "Russian", "Indonesian", "Spanish", "French"]

    /// NLLanguage code to the English name a model understands.
    /// Anything outside this table resolves to nil, meaning: no
    /// language instruction, the model's default behaviour.
    static let names: [String: String] = [
        "en": "English", "de": "German", "es": "Spanish", "fr": "French",
        "ru": "Russian", "id": "Indonesian", "it": "Italian", "pt": "Portuguese",
        "nl": "Dutch", "tr": "Turkish", "pl": "Polish", "sv": "Swedish",
        "da": "Danish", "nb": "Norwegian", "no": "Norwegian", "fi": "Finnish",
        "ja": "Japanese", "ko": "Korean", "zh-Hans": "Chinese", "zh-Hant": "Chinese",
        "ar": "Arabic", "hi": "Hindi", "vi": "Vietnamese", "th": "Thai",
        "uk": "Ukrainian", "cs": "Czech", "ro": "Romanian", "hu": "Hungarian",
    ]

    /// The dominant language of the given lines, as an English name.
    /// Needs a little real text to be sure: under 20 characters of
    /// speech is a greeting or a back-channel, not a language sample,
    /// and an undetermined result stays nil on purpose.
    public static func detect(in lines: [String]) -> String? {
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 20 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return names[language.rawValue]
    }

    /// The language an answer should be written in: the pinned setting
    /// when there is one, otherwise the detected language of the other
    /// side's recent lines, otherwise nil (no instruction).
    public static func resolve(setting: String, themLines: [String]) -> String? {
        let pinned = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pinned.isEmpty { return pinned }
        return detect(in: Array(themLines.suffix(12)))
    }
}
