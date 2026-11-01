import Testing
import Foundation
@testable import BdRemindersCore

struct SyncLogicTests {

    @Test("Extracts Bead ID with brackets")
    func testExtractBeadIDWithBrackets() {
        let title1 = "[proj-en8k] Rebuild shopping-list add bar"
        #expect(extractBeadID(from: title1, prefixes: ["proj"]) == "proj-en8k")

        let title2 = "Fix issue [proj-6iap]"
        #expect(extractBeadID(from: title2, prefixes: ["proj"]) == "proj-6iap")
    }

    @Test("Extracts Bead ID without brackets")
    func testExtractBeadIDWithoutBrackets() {
        let title = "proj-pw2b Curated weekly mealplan"
        #expect(extractBeadID(from: title, prefixes: ["proj"]) == "proj-pw2b")
    }

    @Test("Returns nil when no Bead ID present")
    func testExtractBeadIDNone() {
        let title = "Buy milk and groceries"
        #expect(extractBeadID(from: title, prefixes: ["proj"]) == nil)
    }

    @Test("Ignores hyphenated words that do not use a known issue prefix")
    func testHyphenatedWordsAreNotBeadIDs() {
        let prefixes: Set<String> = ["proj"]
        #expect(extractBeadID(from: "Change the animated ad on in-app recipe browser", prefixes: prefixes) == nil)
        #expect(extractBeadID(from: "Only show category-drag button when list is in edit mode.", prefixes: prefixes) == nil)
        #expect(extractBeadID(from: "[in-app] something", prefixes: prefixes) == nil)
    }

    @Test("Finds a real Bead ID even when hyphenated words come first")
    func testRealIDAfterHyphenatedWord() {
        let title = "[proj-ab12] Fix in-app crash"
        #expect(extractBeadID(from: title, prefixes: ["proj"]) == "proj-ab12")
        #expect(extractBeadID(from: "in-app note, see proj-ab12", prefixes: ["proj"]) == "proj-ab12")
    }

    @Test("Supports multiple prefixes and hierarchical IDs")
    func testMultiplePrefixesAndChildIDs() {
        let prefixes: Set<String> = ["proj", "my-app"]
        #expect(extractBeadID(from: "[my-app-x9z2] Title", prefixes: prefixes) == "my-app-x9z2")
        #expect(extractBeadID(from: "[proj-ab12.3] Child", prefixes: prefixes) == "proj-ab12.3")
    }

    @Test("Without known prefixes only bracketed IDs are recognised")
    func testNoPrefixesBracketOnly() {
        #expect(extractBeadID(from: "[proj-ab12] Title", prefixes: []) == "proj-ab12")
        #expect(extractBeadID(from: "in-app thing", prefixes: []) == nil)
        #expect(extractBeadID(from: "proj-ab12 Title", prefixes: []) == nil)
    }

    @Test("Derives issue prefixes from bead IDs")
    func testPrefixDerivation() {
        let ids = ["buljon-0c1d", "buljon-d8zr", "my-app-x9z2", "proj-ab12.1"]
        #expect(issuePrefixes(fromBeadIDs: ids) == ["buljon", "my-app", "proj"])
    }

    @Test("Maps priority values correctly to EventKit priorities")
    func testPriorityMapping() {
        // P0 / P1 -> High (1)
        #expect(eventKitPriority(for: 0) == 1)
        #expect(eventKitPriority(for: 1) == 1)

        // P2 -> Medium (5)
        #expect(eventKitPriority(for: 2) == 5)

        // P3 / P4 -> Low (9)
        #expect(eventKitPriority(for: 3) == 9)
        #expect(eventKitPriority(for: 4) == 9)

        // Other -> None (0)
        #expect(eventKitPriority(for: 99) == 0)
    }

    @Test("Decodes PriorityValue from integer and string")
    func testPriorityValueDecoding() throws {
        let jsonInt = """
        {"rawValue": 1}
        """
        let decodedInt = try JSONDecoder().decode([String: PriorityValue].self, from: Data(jsonInt.utf8))
        #expect(decodedInt["rawValue"]?.rawValue == 1)

        let jsonString = """
        {"rawValue": "P2"}
        """
        let decodedStr = try JSONDecoder().decode([String: PriorityValue].self, from: Data(jsonString.utf8))
        #expect(decodedStr["rawValue"]?.rawValue == 2)
    }

    @Test("Parses Bead JSON output containing trailing CLI notes")
    func testParseBeadJSONWithTrailingNotes() throws {
        let cliOutput = """
        [
          {
            "id": "proj-en8k",
            "title": "Rebuild shopping-list add bar",
            "description": "Details here",
            "status": "in_progress",
            "priority": 1,
            "issue_type": "bug"
          }
        ]
        NOTE: bd --json output format will change in v2.0. Set BD_JSON_ENVELOPE=1 to opt in early.
        """

        let issues = try parseBeadJSON(from: cliOutput)
        #expect(issues.count == 1)
        #expect(issues.first?.id == "proj-en8k")
        #expect(issues.first?.title == "Rebuild shopping-list add bar")
        #expect(issues.first?.status == "in_progress")
        #expect(issues.first?.priority.rawValue == 1)
        #expect(issues.first?.issueType == "bug")
    }

    @Test("SyncConfiguration derives default list name from project directory")
    func testSyncConfigurationDefaults() {
        let config = SyncConfiguration(projectDirectory: "/path/to/my-cool-project")
        #expect(config.targetListName == "my-cool-project")
        #expect(config.isDryRun == false)

        let explicit = SyncConfiguration(projectDirectory: "/path/to/my-cool-project", targetListName: "CustomList", isDryRun: true)
        #expect(explicit.targetListName == "CustomList")
        #expect(explicit.isDryRun == true)
    }
}
