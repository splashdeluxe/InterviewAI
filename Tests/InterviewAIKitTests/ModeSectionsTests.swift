import Foundation
import Testing
@testable import InterviewAIKit

@Test("Section titles come out of a built-in template, placeholders skipped")
func sectionTitlesFromBuiltIn() {
    #expect(ModeSections.titles(from: BuiltInModes.mode(id: "looking-for-work").notesTemplate)
        == ["Role", "Questions asked", "My best answers", "Follow-ups I owe"])
    #expect(ModeSections.titles(from: BuiltInModes.mode(id: "general").notesTemplate)
        == ["Decisions", "Open points"])
    #expect(ModeSections.titles(from: BuiltInModes.mode(id: "team-meet").notesTemplate)
        == ["Decisions", "Action items"])
}

@Test("Empty and bullet-only templates have no sections")
func sectionTitlesEmpty() {
    #expect(ModeSections.titles(from: "") == [])
    #expect(ModeSections.titles(from: "-\n- [ ] \n") == [])
}

@Test("Titles are trimmed and keep their order")
func sectionTitlesTrimmed() {
    #expect(ModeSections.titles(from: "  Problem  \n\nApproach\nComplexity\n") == ["Problem", "Approach", "Complexity"])
}
