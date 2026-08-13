import XCTest
@testable import Sage

final class SaveSkillActionTests: XCTestCase {
    private struct Args: Decodable {
        let action: SaveSkillAction
        let name: String
        let description: String
        let body: String
        let scope: SkillScope?
    }

    func testDecodeCreateWithProjectScope() throws {
        let json = """
        {"action":"create","name":"demo-skill","description":"When to use","body":"# Steps","scope":"project"}
        """
        let args = try decodeToolArgs(json, as: Args.self)
        XCTAssertEqual(args.action, .create)
        XCTAssertEqual(args.scope, .project)
        XCTAssertEqual(args.name, "demo-skill")
    }

    func testDecodeEnhanceOmitsScope() throws {
        let json = """
        {"action":"enhance","name":"demo-skill","description":"When to use","body":"# Steps"}
        """
        let args = try decodeToolArgs(json, as: Args.self)
        XCTAssertEqual(args.action, .enhance)
        XCTAssertNil(args.scope)
    }

    func testDecodeRejectsInvalidAction() {
        let json = """
        {"action":"merge","name":"demo-skill","description":"When to use","body":"# Steps"}
        """
        XCTAssertThrowsError(try decodeToolArgs(json, as: Args.self))
    }

    func testExtractionParsingNormalizeAndActions() {
        XCTAssertEqual(
            SkillExtractionParsing.normalizeSkillName(" Hello_World!! "),
            "hello-world"
        )
        XCTAssertEqual(
            SkillExtractionParsing.parseResponse(#"{"action":"skip","reason":"x"}"#),
            .skip
        )
        if case .newSkill(let name, let description) = SkillExtractionParsing.parseResponse(
            #"{"action":"new","name":"My Skill","description":"Use when testing"}"#
        ) {
            XCTAssertEqual(name, "my-skill")
            XCTAssertEqual(description, "Use when testing")
        } else {
            XCTFail("expected newSkill")
        }
    }
}
