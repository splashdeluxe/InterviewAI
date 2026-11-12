import Foundation
import Testing
@testable import InterviewAIKit

/// The first-run wizard's data and gating: every language pick maps
/// to a real answer language, every purpose card points at a real
/// built-in mode, and only the permissions step can block Continue.
struct OnboardingTests {
    @Test("Wizard languages are unique and map to answer languages")
    func languages() {
        let all = OnboardingLanguage.all
        #expect(all.count == 6)
        #expect(Set(all.map(\.locale)).count == all.count)
        #expect(OnboardingLanguage.matching(locale: "de-DE")?.answerLanguage == "German")
        #expect(OnboardingLanguage.matching(locale: "en-GB")?.answerLanguage == "English")
        #expect(OnboardingLanguage.matching(locale: "fr-FR") == nil)
        for language in all {
            #expect(AnswerLanguage.languages.contains(language.answerLanguage))
        }
    }

    @Test("Every purpose card points at a real built-in mode")
    func purposes() {
        let builtInIDs = Set(BuiltInModes.all.map(\.id))
        #expect(OnboardingPurpose.all.count == 6)
        #expect(Set(OnboardingPurpose.all.map(\.modeID)).count == 6)
        for purpose in OnboardingPurpose.all {
            #expect(builtInIDs.contains(purpose.modeID))
            #expect(!purpose.line.isEmpty)
        }
    }

    @Test("Only the permissions step gates Continue")
    func gating() {
        for step in 0..<OnboardingFlow.stepCount where step != OnboardingFlow.permissionsStep {
            #expect(OnboardingFlow.canContinue(step: step, micGranted: false, screenGranted: false))
        }
        #expect(!OnboardingFlow.canContinue(step: OnboardingFlow.permissionsStep, micGranted: true, screenGranted: false))
        #expect(!OnboardingFlow.canContinue(step: OnboardingFlow.permissionsStep, micGranted: false, screenGranted: true))
        #expect(OnboardingFlow.canContinue(step: OnboardingFlow.permissionsStep, micGranted: true, screenGranted: true))
    }
}
