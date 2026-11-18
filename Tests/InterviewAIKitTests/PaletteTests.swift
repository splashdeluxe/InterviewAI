import Foundation
import Testing
@testable import InterviewAIKit

private func item(_ id: String, _ title: String, keywords: String = "") -> PaletteItem {
    PaletteItem(id: id, title: title, subtitle: "", group: "Test", keywords: keywords)
}

@Test("An empty query keeps the supplied order untouched")
func paletteEmptyQuery() {
    let items = [item("b", "Meetings"), item("a", "Ask")]
    #expect(PaletteFilter.ranked(items, query: "") == items)
    #expect(PaletteFilter.ranked(items, query: "  ") == items)
}

@Test("Title prefixes beat word prefixes, which beat containment")
func paletteRankingTiers() {
    let items = [
        item("contains", "Uncleanable Notes"),
        item("word", "Transcript Clean Up"),
        item("prefix", "Clean Transcript"),
        item("none", "Regenerate Summary"),
    ]
    let ranked = PaletteFilter.ranked(items, query: "clean")
    #expect(ranked.map(\.id) == ["prefix", "word", "contains"])
}

@Test("A keyword hit ranks below a title hit but still matches")
func paletteKeywordMatch() {
    let items = [
        item("kw", "Context", keywords: "documents files cv resume"),
        item("title", "Files and Folders"),
    ]
    let ranked = PaletteFilter.ranked(items, query: "files")
    #expect(ranked.map(\.id) == ["title", "kw"])
}

@Test("A subsequence of the title matches, unrelated items do not")
func paletteSubsequence() {
    let items = [
        item("sub", "Command Palette"),
        item("no", "Meetings"),
    ]
    let ranked = PaletteFilter.ranked(items, query: "cmp")
    #expect(ranked.map(\.id) == ["sub"])
}

@Test("Matching ignores case and extra spaces")
func paletteNormalization() {
    let items = [item("a", "Find Questions")]
    #expect(PaletteFilter.ranked(items, query: "  FIND  ").map(\.id) == ["a"])
    #expect(PaletteFilter.ranked(items, query: "questions").map(\.id) == ["a"])
}
