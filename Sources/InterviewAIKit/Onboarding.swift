import Foundation

/// One language pick in the first-run wizard. A single pick sets two
/// settings that otherwise live apart: the speech locale the
/// transcription listens for, and the language answers are written
/// in. Settings keeps them separate afterwards for fine-tuning.
public struct OnboardingLanguage: Equatable, Sendable, Identifiable {
    public let locale: String
    public let name: String
    public let answerLanguage: String

    public var id: String { locale }

    public init(locale: String, name: String, answerLanguage: String) {
        self.locale = locale
        self.name = name
        self.answerLanguage = answerLanguage
    }

    /// The same six languages the Speech settings offer.
    public static let all: [OnboardingLanguage] = [
        OnboardingLanguage(locale: "en-US", name: "English (US)", answerLanguage: "English"),
        OnboardingLanguage(locale: "en-GB", name: "English (UK)", answerLanguage: "English"),
        OnboardingLanguage(locale: "de-DE", name: "German", answerLanguage: "German"),
        OnboardingLanguage(locale: "ru-RU", name: "Russian", answerLanguage: "Russian"),
        OnboardingLanguage(locale: "id-ID", name: "Indonesian", answerLanguage: "Indonesian"),
        OnboardingLanguage(locale: "es-ES", name: "Spanish", answerLanguage: "Spanish"),
    ]

    public static func matching(locale: String) -> OnboardingLanguage? {
        all.first { $0.locale == locale }
    }
}

/// One purpose card in the wizard. The pick sets the default mode,
/// so a first run never lands on General by accident. The line is
/// written as an outcome, one per card.
public struct OnboardingPurpose: Equatable, Sendable, Identifiable {
    public let title: String
    public let line: String
    public let modeID: String

    public var id: String { modeID }

    public init(title: String, line: String, modeID: String) {
        self.title = title
        self.line = line
        self.modeID = modeID
    }

    public static let all: [OnboardingPurpose] = [
        OnboardingPurpose(title: "Job interview", line: "You are the candidate. Answers in your voice, grounded in your CV.", modeID: "looking-for-work"),
        OnboardingPurpose(title: "Technical interview", line: "Depth without rambling, worked examples included.", modeID: "technical-interview"),
        OnboardingPurpose(title: "Hiring", line: "You ask the questions. Sharper follow ups, better notes.", modeID: "recruiting"),
        OnboardingPurpose(title: "Sales", line: "Objections handled, the next step kept alive.", modeID: "sales"),
        OnboardingPurpose(title: "Team meetings", line: "Decisions, owners and action items, caught as they happen.", modeID: "team-meet"),
        OnboardingPurpose(title: "Lectures", line: "Follow the thread and keep the points that matter.", modeID: "lecture"),
    ]
}

/// The wizard's flow rules: six steps, and only the permissions step
/// can hold Continue back, exactly as the proven permission card did.
public enum OnboardingFlow {
    public static let stepCount = 6
    public static let permissionsStep = 3

    public static func canContinue(step: Int, micGranted: Bool, screenGranted: Bool) -> Bool {
        guard step == permissionsStep else { return true }
        return micGranted && screenGranted
    }
}
