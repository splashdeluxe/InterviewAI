import Testing
@testable import InterviewAIKit

@Test("A full theme reply parses with its moments sorted and deduped")
func themeFullParse() {
    let raw = """
        {"themes": [
          {"t": "Salary band", "d": "The band is 85,000, with 95,000 called possible but not promised.", "at": [900, 300, 900]},
          {"t": "Planning work", "d": "The role owns planning and sales operations end to end.", "at": [120]}
        ]}
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 2)
    #expect(themes?.first?.title == "Salary band")
    #expect(themes?.first?.atSeconds == [300, 900])
}

@Test("A theme whose moments all fall outside the call is dropped")
func themeOutOfRangeDropped() {
    let raw = """
        {"themes": [
          {"t": "Real topic", "d": "A topic the call genuinely spent time on.", "at": [60]},
          {"t": "Invented topic", "d": "A topic resting on a moment that never happened.", "at": [99999]}
        ]}
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 1)
    #expect(themes?.first?.title == "Real topic")
}

@Test("Duplicate titles collapse and fragment details are dropped")
func themeDedupeAndFragments() {
    let raw = """
        {"themes": [
          {"t": "Salary band", "d": "The band is 85,000, with 95,000 called possible.", "at": [300]},
          {"t": "salary band", "d": "The same topic named a second time over.", "at": [400]},
          {"t": "Thin", "d": "short", "at": [500]}
        ]}
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 1)
    #expect(themes?.first?.atSeconds == [300])
}

@Test("A single moment handed back as one number still counts")
func themeSingleMoment() {
    let raw = """
        {"themes": [{"t": "Next steps", "d": "A follow-up call with the VP was agreed for Thursday.", "at": 1250}]}
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 1)
    #expect(themes?.first?.atSeconds == [1250])
}

@Test("A fenced reply parses, and an empty reply is an empty list, not nil")
func themeFencesAndEmpty() {
    let fenced = "Here are the themes:\n```json\n{\"themes\": []}\n```"
    #expect(ThemeParsing.parse(fenced, maxSeconds: 600)?.isEmpty == true)
    #expect(ThemeParsing.parse("No JSON in this reply at all.", maxSeconds: 600) == nil)
}

@Test("Themes survive an encode and decode round trip")
func themeRoundTrip() {
    let themes = [MeetingTheme(title: "Salary band", detail: "The band is 85,000.", atSeconds: [300, 900])]
    #expect(MeetingTheme.decode(MeetingTheme.encode(themes)) == themes)
    let merged = ThemeParsing.parse(ThemeParsing.encodeThemes(themes), maxSeconds: 1320)
    #expect(merged == themes)}

@Test("The theme prompts carry the no-invention and seconds rules")
func themePromptGuardrails() {
    #expect(ThemePrompts.system.contains("Never invent"))
    #expect(ThemePrompts.system.contains("[seconds]"))
    #expect(ThemeMergePrompts.system.contains("never invent"))
}

@Test("A bare list reply parses as if it were wrapped in the object")
func themeBareArray() {
    let raw = """
        [{"t": "Salary band", "d": "The band is 85,000, with 95,000 called possible.", "at": [300]}]
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 1)
    #expect(themes?.first?.title == "Salary band")
}

@Test("Prose carrying braces of its own does not bury the real object")
func themeProseWithBraces() {
    let raw = """
        The themes {in brief} are these: {"themes": [{"t": "Next steps", "d": "A follow-up call with the VP was agreed for Thursday.", "at": [1250]}]} as requested.
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 1)
    #expect(themes?.first?.title == "Next steps")
}

@Test("One malformed theme does not sink the themes beside it")
func themeLossyElements() {
    let raw = """
        {"themes": [
          {"t": 42, "d": "A title handed back as a number instead of words.", "at": [100]},
          {"t": "Salary band", "d": "The band is 85,000, with 95,000 called possible.", "at": [300]}
        ]}
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 1)
    #expect(themes?.first?.title == "Salary band")
}

@Test("A reply cut off mid-theme still yields the themes it finished")
func themeTruncationSalvage() {
    let raw = """
        {"themes": [
          {"t": "Salary band", "d": "The band is 85,000, with 95,000 called possible.", "at": [300]},
          {"t": "Planning work", "d": "The role owns planning and sales oper
        """
    let themes = ThemeParsing.parse(raw, maxSeconds: 1320)
    #expect(themes?.count == 1)
    #expect(themes?.first?.title == "Salary band")
}
