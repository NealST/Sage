@testable import Sage
import XCTest

final class SkillMarkdownTests: XCTestCase {
    func testParsesTopLevelRequiredSecrets() {
        let parsed = SkillMarkdown.parseFrontmatter(
            """
            ---
            name: demo
            description: Demo
            required-secrets: GITHUB_TOKEN, NPM_TOKEN
            ---
            Body
            """
        )

        XCTAssertEqual(parsed.scalars["required-secrets"], "GITHUB_TOKEN, NPM_TOKEN")
    }

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

    func testRenderDocumentReplacesManagedFieldsAndPreservesUnknownFields() {
        let original = """
        ---
        name: demo
        description: old
        allowed-tools: shell
        metadata:
          owner: old
        custom-setting: keep-me
        ---
        Old body
        """

        let document = SkillMarkdown.Document(
            originalText: original,
            name: "demo",
            description: "new: description",
            license: "Apache-2.0",
            compatibility: nil,
            allowedTools: "read_file run_shell_command",
            metadata: ["owner": "sage"],
            source: nil,
            body: "# New body"
        )
        let result = SkillMarkdown.renderDocument(document)

        XCTAssertTrue(result.contains("description: \"new: description\""))
        XCTAssertTrue(result.contains("license: Apache-2.0"))
        XCTAssertTrue(result.contains("allowed-tools: read_file run_shell_command"))
        XCTAssertTrue(result.contains("  owner: sage"))
        XCTAssertTrue(result.contains("custom-setting: keep-me"))
        XCTAssertTrue(result.contains("# New body"))
        XCTAssertFalse(result.contains("owner: old"))
        XCTAssertFalse(result.contains("Old body"))
    }

    func testRenderDocumentDoesNotDuplicateManagedFields() {
        let original = """
        ---
        name: demo
        description: |
          old
          description
        source: auto-generated
        ---
        Body
        """

        let document = SkillMarkdown.Document(
            originalText: original,
            name: "demo",
            description: "updated",
            license: nil,
            compatibility: nil,
            allowedTools: nil,
            metadata: [:],
            source: "auto-generated",
            body: "Body"
        )
        let result = SkillMarkdown.renderDocument(document)

        XCTAssertEqual(result.components(separatedBy: "description:").count - 1, 1)
        XCTAssertEqual(result.components(separatedBy: "source:").count - 1, 1)
    }
}
