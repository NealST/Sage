import XCTest
@testable import Sage

final class WorkingMemoryParserTests: XCTestCase {
    private let from = UUID()
    private let through = UUID()

    func testParsesJSONInsideSummary() {
        let raw = """
        <analysis>state looks fine</analysis>
        <summary>
        {
          "overview": "Clean Downloads",
          "focus": "Waiting to delete installers",
          "nextSteps": "Ask before deleting"
        }
        </summary>
        """
        let memory = WorkingMemoryParser.parse(
            raw,
            foldedFromEventID: from,
            foldedThroughEventID: through,
            sourceModel: "test-model"
        )
        XCTAssertEqual(memory?.mode, .structured)
        XCTAssertEqual(memory?.overview, "Clean Downloads")
        XCTAssertEqual(memory?.focus, "Waiting to delete installers")
        XCTAssertEqual(memory?.nextSteps, "Ask before deleting")
        XCTAssertEqual(memory?.sourceModel, "test-model")
        XCTAssertEqual(memory?.foldedFromEventID, from)
        XCTAssertEqual(memory?.foldedThroughEventID, through)
    }

    func testParsesSnakeCaseJSONKeys() {
        let raw = """
        <summary>{"overview":"Goal","touched_files":"~/Downloads","recent_actions":"listed"}</summary>
        """
        let memory = WorkingMemoryParser.parse(
            raw,
            foldedFromEventID: from,
            foldedThroughEventID: through,
            sourceModel: nil
        )
        XCTAssertEqual(memory?.touchedFiles, "~/Downloads")
        XCTAssertEqual(memory?.recentActions, "listed")
    }

    func testParsesLabeledHeadings() {
        let raw = """
        Overview: Clean Downloads
        Touched files: listed ~/Downloads
        Next steps: Confirm before delete
        """
        let memory = WorkingMemoryParser.parse(
            raw,
            foldedFromEventID: from,
            foldedThroughEventID: through,
            sourceModel: nil
        )
        XCTAssertEqual(memory?.mode, .structured)
        XCTAssertEqual(memory?.overview, "Clean Downloads")
        XCTAssertEqual(memory?.touchedFiles, "listed ~/Downloads")
        XCTAssertEqual(memory?.nextSteps, "Confirm before delete")
    }

    func testFallsBackToSimpleProse() {
        let raw = """
        <analysis>notes</analysis>
        <summary>
        User asked to tidy Downloads; listed files; waiting to delete.
        </summary>
        """
        let memory = WorkingMemoryParser.parse(
            raw,
            foldedFromEventID: from,
            foldedThroughEventID: through,
            sourceModel: "test-model"
        )
        XCTAssertEqual(memory?.mode, .simple)
        XCTAssertEqual(
            memory?.narrative,
            "User asked to tidy Downloads; listed files; waiting to delete."
        )
    }

    func testReturnsNilWhenNothingUsableRemains() {
        XCTAssertNil(
            WorkingMemoryParser.parse(
                "<summary>   </summary>",
                foldedFromEventID: from,
                foldedThroughEventID: through,
                sourceModel: nil
            )
        )
    }
}
