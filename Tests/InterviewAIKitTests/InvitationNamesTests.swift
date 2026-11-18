import XCTest
@testable import InterviewAIKit

/// Names mined from invitation text. The cases mirror the shapes
/// real invitations use, with invented names: a "with" phrase in
/// the title, a pair joined by +, the "— Name," title pattern, a
/// particle name, an "arranged by" credit in the details, and the
/// texts that must yield nothing.
final class InvitationNamesTests: XCTestCase {

    func testWithPhraseInTitle() {
        XCTAssertEqual(
            SpeakerNames.minedNames(title: "Interview: Acme - TA Interview with Dana Berger", details: ""),
            ["Dana Berger"])
        XCTAssertEqual(
            SpeakerNames.minedNames(title: "Call with Tom", details: ""),
            ["Tom"])
    }

    func testWithPairJoinedByPlus() {
        XCTAssertEqual(
            SpeakerNames.minedNames(
                title: "Interview: Ops - Product Manager first call with Petra + Jonas",
                details: "First video call with Petra Lang (Head of People) and Jonas (Talent Acquisition)."),
            ["Petra", "Jonas", "Petra Lang"])
    }

    func testDashPatternInTitle() {
        XCTAssertEqual(
            SpeakerNames.minedNames(title: "ML9 interview — Karl Brandt, Senior Product Manager", details: ""),
            ["Karl Brandt"])
        // No comma after the name: not the pattern.
        XCTAssertEqual(
            SpeakerNames.minedNames(title: "Review — Karl Brandt presents the roadmap", details: ""),
            [])
    }

    func testParticleName() {
        XCTAssertEqual(
            SpeakerNames.minedNames(title: "Interview: Docflix - intro with Martin von Aren", details: ""),
            ["Martin von Aren"])
    }

    func testArrangedByInDetailsAndRoleWordsStopNames() {
        let mined = SpeakerNames.minedNames(
            title: "KNIME talk - Director, Product (call with Chris)",
            details: "30-min call with hiring manager Chris, arranged by Lena Hartmann, Senior HR Specialist.")
        XCTAssertEqual(mined, ["Chris", "Lena Hartmann"])
    }

    func testDetailsWithPhrase() {
        XCTAssertEqual(
            SpeakerNames.minedNames(
                title: "Interview: thermos - Excellence Manager (Planung) with Alex Brandt",
                details: "Intro call, 30 min with Alex Brandt (Talent Acquisition Manager), German, du form."),
            ["Alex Brandt"])
    }

    func testNothingToMine() {
        XCTAssertEqual(SpeakerNames.minedNames(title: "Veterans Day", details: ""), [])
        XCTAssertEqual(SpeakerNames.minedNames(title: "Boris Lindner's Birthday", details: "addressbook://x"), [])
        XCTAssertEqual(
            SpeakerNames.minedNames(
                title: "Rally Tournament",
                details: "Category: Silver Men — REGISTERED. Player 1: Nils, Player 2: Daniel."),
            [])
        XCTAssertEqual(
            SpeakerNames.minedNames(title: "Weekly sync with the Team", details: "Bring notes."),
            [])
        XCTAssertEqual(
            SpeakerNames.minedNames(title: "Intro call with Google Meet", details: ""),
            [])
    }

    func testInvitationCandidatesMergeAndClean() {
        // Attendee list empty, as real invitations leave it: the
        // text alone supplies the person.
        XCTAssertEqual(
            SpeakerNames.invitationCandidates(
                attendees: [], title: "Interview with Dana Berger",
                details: "Booked by Nils via Dana's link.", myName: "Nils Effmert"),
            ["Dana Berger"])
        // A lone first name the full name covers is dropped.
        XCTAssertEqual(
            SpeakerNames.invitationCandidates(
                attendees: [], title: "Call with Petra + Jonas",
                details: "First call with Petra Lang (Head of People) and Jonas."),
            ["Jonas", "Petra Lang"])
        // The user's own name never survives, full or first name.
        XCTAssertEqual(
            SpeakerNames.invitationCandidates(
                attendees: ["Nils Effmert", "Dana Berger"], myName: "Nils Effmert"),
            ["Dana Berger"])
    }
}
