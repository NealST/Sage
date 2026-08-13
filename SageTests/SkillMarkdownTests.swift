import XCTest
@testable import Sage

final class SkillMarkdownTests: XCTestCase {
    func testValidSkillNames() {
        XCTAssertTrue(SkillMarkdown.isValidSkillName("ok-name"))
        XCTAssertTrue(SkillMarkdown.isValidSkillName("a1"))
        XCTAssertFalse(SkillMarkdown.isValidSkillName("-bad"))
        XCTAssertFalse(SkillMarkdown.isValidSkillName("bad-"))
        XCTAssertFalse(SkillMarkdown.isValidSkillName("Bad"))
        XCTAssertFalse(SkillMarkdown.isValidSkillName("has--double"))
        XCTAssertFalse(SkillMarkdown.isValidSkillName(""))
    }

    func testFrontmatterStripAndRange() {
        let text = """
        ---
        name: demo
        description: hello
        ---
        # Body

        more
        """
        XCTAssertNotNil(SkillMarkdown.frontmatterRange(text))
        let body = SkillMarkdown.stripFrontmatter(text)
        XCTAssertTrue(body.hasPrefix("# Body"))
        XCTAssertFalse(body.contains("name: demo"))
    }

    func testYAMLScalarQuoting() {
        XCTAssertEqual(SkillMarkdown.yamlScalar("plain"), "plain")
        XCTAssertTrue(SkillMarkdown.yamlScalar("needs: quote").hasPrefix("\""))
    }
}
