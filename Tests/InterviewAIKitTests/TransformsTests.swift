import Foundation
import Testing
@testable import InterviewAIKit

private func segment(_ channel: String, _ text: String, offset: Double) -> TranscriptSegment {
    TranscriptSegment(channel: channel, text: text, isFinal: true, startOffset: offset)
}

@Test("Transform results round trip through their store JSON")
func transformResultRoundTrip() {
    let results = [
        TransformResult(id: "one", name: "Brief Summary", prompt: "At most 5 short lines.",
                        text: "We agreed the band and the start date.", source: .cleaned,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000)),
        TransformResult(id: "two", name: "Thank-You Email", prompt: "Warm and short.",
                        text: "Dear Alex, thank you for your time today.", source: .original,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_100)),
    ]
    #expect(TransformResult.decode(TransformResult.encode(results)) == results)
}

@Test("Empty and garbage result JSON decodes to no results")
func transformResultGarbageDecodesEmpty() {
    #expect(TransformResult.decode("").isEmpty)
    #expect(TransformResult.decode("not json at all").isEmpty)
    #expect(TransformResult.decode("[{\"name\": 3}]").isEmpty)
}

@Test("A transform result gets an id and a date by default")
func transformResultDefaults() {
    let result = TransformResult(name: "Brief Summary", prompt: "Short.", text: "Text.", source: .original)
    #expect(!result.id.isEmpty)
    #expect(abs(result.createdAt.timeIntervalSinceNow) < 60)
}

@Test("Transform favorites round trip through their store JSON")
func transformFavoriteRoundTrip() {
    let favorites = [
        TransformFavorite(id: "fav-one", name: "Action list", prompt: "List every action with its owner."),
        TransformFavorite(id: "fav-two", name: "One paragraph", prompt: "Turn this into one paragraph."),
    ]
    #expect(TransformFavorite.decode(TransformFavorite.encode(favorites)) == favorites)
    #expect(TransformFavorite.decode("").isEmpty)
    #expect(TransformFavorite.decode("garbage").isEmpty)
}

@Test("The built-in transforms are the five, in order, each with an instruction")
func builtInTransformsShape() {
    #expect(BuiltInTransforms.all.count == 5)
    #expect(BuiltInTransforms.all.map(\.id) == ["briefSummary", "detailedSummary", "thankYouEmail", "followUpEmail", "studyQuestions"])
    #expect(BuiltInTransforms.all == [BuiltInTransforms.briefSummary, BuiltInTransforms.detailedSummary,
                                      BuiltInTransforms.thankYouEmail, BuiltInTransforms.followUpEmail,
                                      BuiltInTransforms.studyQuestions])
    for definition in BuiltInTransforms.all {
        #expect(!definition.name.isEmpty)
        #expect(!definition.instruction.isEmpty)
    }
}

@Test("Translate and tone definitions carry the picked language and tone")
func translateAndToneDefinitions() {
    let translate = BuiltInTransforms.translate(language: "German")
    #expect(translate.id == "translate")
    #expect(translate.name == "Translate Summary")
    #expect(translate.instruction.contains("German"))

    #expect(BuiltInTransforms.tones == ["Professional", "Casual", "Confident"])
    let tone = BuiltInTransforms.toneRewrite(tone: "Confident")
    #expect(tone.id == "tone")
    #expect(tone.name == "Rewrite — Confident")
    #expect(tone.instruction.contains("Confident"))
}

@Test("The transform system prompt fences the model to the text given")
func transformSystemFence() {
    #expect(TransformPrompt.system.contains("Work only from the text given to you"))
    #expect(TransformPrompt.system.contains("Never invent names, numbers, decisions, or roles"))
    #expect(TransformPrompt.system.contains("instead of guessing"))
}

@Test("The user message carries title, attendees, instruction and the input text")
func transformUserMessageFull() {
    let message = TransformPrompt.userMessage(
        definition: BuiltInTransforms.thankYouEmail,
        inputLabel: TransformSource.cleaned.label,
        inputText: "Alex: Thanks for coming in today.",
        title: "thermondo Fachinterview",
        attendees: ["Yannick Skop", "Alexander Mandry"]
    )
    #expect(message.contains("thermondo Fachinterview"))
    #expect(message.contains("Yannick Skop"))
    #expect(message.contains("Alexander Mandry"))
    #expect(message.contains(BuiltInTransforms.thankYouEmail.instruction))
    #expect(message.contains("Clean Transcript"))
    #expect(message.contains("Alex: Thanks for coming in today."))
}

@Test("The user message leaves title and attendees out when there are none")
func transformUserMessageBare() {
    let message = TransformPrompt.userMessage(
        definition: BuiltInTransforms.briefSummary,
        inputLabel: TransformSource.original.label,
        inputText: "Them: Let us start.",
        title: "",
        attendees: []
    )
    #expect(!message.contains("Meeting:"))
    #expect(!message.contains("Attendees:"))
    #expect(message.contains(BuiltInTransforms.briefSummary.instruction))
    #expect(message.contains("Original transcript"))
    #expect(message.contains("Them: Let us start."))
}

@Test("The source picker prefers the Clean Transcript")
func sourcePickerPrefersCleaned() {
    let cleaned = [segment("them", "Cleaned line.", offset: 0)]
    let original = [segment("them", "Original line.", offset: 0)]
    let picked = TransformSourcePicker.pick(cleaned: cleaned, original: original)
    #expect(picked?.source == .cleaned)
    #expect(picked?.segments == cleaned)
}

@Test("The source picker falls back to the original transcript")
func sourcePickerFallsBackToOriginal() {
    let original = [segment("me", "My line.", offset: 0)]
    let picked = TransformSourcePicker.pick(cleaned: [], original: original)
    #expect(picked?.source == .original)
    #expect(picked?.segments == original)
}

@Test("The source picker finds nothing when both transcripts are empty")
func sourcePickerEmpty() {
    #expect(TransformSourcePicker.pick(cleaned: [], original: []) == nil)
}

@Test("Source labels name the sources as the meeting page shows them")
func transformSourceLabels() {
    #expect(TransformSource.cleaned.label == "Clean Transcript")
    #expect(TransformSource.original.label == "Original transcript")
    #expect(TransformSource.summary.label == "Summary")
}
