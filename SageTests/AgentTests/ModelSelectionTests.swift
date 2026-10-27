@testable import Sage
import XCTest

final class ModelSelectionTests: XCTestCase {
    func testMigrationMapsLegacyStringsToCloudSelections() {
        let result = ModelSelectionMigration.migrate(.init(
            defaultModel: "gpt-4.1-mini",
            planModel: "gpt-4.1",
            executeModel: "gpt-4.1",
            reviewModel: "o4-mini"
        ))

        XCTAssertEqual(result.defaultSelection, .cloud("gpt-4.1-mini"))
        XCTAssertEqual(result.planSelection, .cloud("gpt-4.1"))
        XCTAssertEqual(result.executeSelection, .cloud("gpt-4.1"))
        XCTAssertEqual(result.reviewSelection, .cloud("o4-mini"))
    }

    func testMigrationTreatsEmptyRoleStringsAsFollowDefault() {
        let result = ModelSelectionMigration.migrate(.init(
            defaultModel: "claude-sonnet-4-5",
            planModel: "",
            executeModel: nil,
            reviewModel: "  "
        ))

        XCTAssertEqual(result.defaultSelection, .cloud("claude-sonnet-4-5"))
        XCTAssertNil(result.planSelection)
        XCTAssertNil(result.executeSelection)
        XCTAssertNil(result.reviewSelection)
    }

    func testMigrationFallsBackWhenNothingStored() {
        let result = ModelSelectionMigration.migrate(.init(
            defaultModel: "",
            planModel: nil,
            executeModel: nil,
            reviewModel: nil
        ))

        XCTAssertEqual(result.defaultSelection, .cloud("gpt-4.1-mini"))
        XCTAssertNil(result.planSelection)
        XCTAssertNil(result.executeSelection)
        XCTAssertNil(result.reviewSelection)
    }

    func testCodableRoundTrip() throws {
        let selection = ModelSelection.local("mlx-community/Qwen3-4B-4bit")
        let data = try XCTUnwrap(selection.encoded())
        let decoded = try XCTUnwrap(ModelSelection.decode(from: data))
        XCTAssertEqual(decoded, selection)
    }

    func testDisplayName() {
        XCTAssertEqual(
            ModelSelection.local("mlx-community/Qwen3-4B-4bit").displayName,
            "Qwen3-4B-4bit"
        )
        XCTAssertEqual(ModelSelection.cloud("gpt-4.1-mini").displayName, "gpt-4.1-mini")
    }
}
