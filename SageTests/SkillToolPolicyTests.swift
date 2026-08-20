@testable import Sage
import XCTest

final class SkillToolPolicyTests: XCTestCase {
    func testForkedLoadSkillDoesNotActivateInParent() {
        XCTAssertEqual(
            SkillToolExecutor.loadSkillName(from: #"{"name":"demo"}"#),
            "demo"
        )
        XCTAssertNil(
            SkillToolExecutor.loadSkillName(
                from: #"{"name":"demo","mode":"fork","task":"inspect"}"#
            )
        )
    }

    private func skill(
        name: String,
        allowedTools: String? = nil
    ) -> SkillRecord {
        SkillRecord(
            name: name,
            description: "test",
            path: "/tmp/\(name)/SKILL.md",
            enabled: true,
            scope: .global,
            allowedTools: allowedTools
        )
    }

    func testNoRestrictionWhenAllowedToolsEmpty() {
        let allowed = SkillToolPolicy.restrictedToolNames(
            activatedSkillNames: ["demo"],
            enabledSkills: [skill(name: "demo")]
        )
        XCTAssertNil(allowed)
    }

    func testAliasesMapToRegistryNames() {
        XCTAssertEqual(SkillToolPolicy.canonicalizeToolName("shell"), "run_shell_command")
        XCTAssertEqual(SkillToolPolicy.canonicalizeToolName("read"), "read_text_file")
        XCTAssertEqual(SkillToolPolicy.canonicalizeToolName("write"), "write_text_file")
        XCTAssertEqual(
            SkillToolPolicy.canonicalizeToolName("run_shell_command"),
            "run_shell_command"
        )
    }

    func testUnionIncludesSkillToolsAndDeclaredAliases() {
        let allowed = SkillToolPolicy.restrictedToolNames(
            activatedSkillNames: ["demo"],
            enabledSkills: [skill(name: "demo", allowedTools: "read shell")]
        )
        XCTAssertEqual(
            allowed,
            Set(["read_text_file", "run_shell_command"])
                .union(SkillToolPolicy.progressiveDisclosureToolNames)
        )
        XCTAssertFalse(allowed?.contains("run_skill_script") == true)
        XCTAssertFalse(allowed?.contains("save_skill") == true)
    }

    func testAssertAndFilterDefinitions() throws {
        let skills = [skill(name: "demo", allowedTools: "read_text_file")]
        try SkillToolPolicy.assertToolAllowed(
            "read_text_file",
            activatedSkillNames: ["demo"],
            enabledSkills: skills
        )
        XCTAssertThrowsError(
            try SkillToolPolicy.assertToolAllowed(
                "run_shell_command",
                activatedSkillNames: ["demo"],
                enabledSkills: skills
            )
        )

        XCTAssertThrowsError(
            try SkillToolPolicy.assertToolAllowed(
                "run_skill_script",
                activatedSkillNames: ["demo"],
                enabledSkills: skills
            )
        )

        let defs = [
            ToolDefinition(name: "read_text_file", description: "r", parameters: .schemaObject(properties: [:])),
            ToolDefinition(name: "run_shell_command", description: "s", parameters: .schemaObject(properties: [:])),
            ToolDefinition(name: "save_skill", description: "k", parameters: .schemaObject(properties: [:])),
            ToolDefinition(name: "run_skill_script", description: "x", parameters: .schemaObject(properties: [:])),
        ]
        let filtered = SkillToolPolicy.filterDefinitions(
            defs,
            activatedSkillNames: ["demo"],
            enabledSkills: skills
        )
        XCTAssertEqual(filtered.map(\.name), ["read_text_file"])
    }

    func testExplicitAllowedToolsCanIncludeSkillScript() throws {
        let skills = [skill(name: "demo", allowedTools: "read run_skill_script")]
        try SkillToolPolicy.assertToolAllowed(
            "run_skill_script",
            activatedSkillNames: ["demo"],
            enabledSkills: skills
        )
    }

    func testRecallStaysAvailableUnderSkillRestriction() throws {
        let skills = [skill(name: "demo", allowedTools: "read_text_file")]
        try SkillToolPolicy.assertToolAllowed(
            RecallTaskTranscriptTool.name,
            activatedSkillNames: ["demo"],
            enabledSkills: skills
        )
        try SkillToolPolicy.assertToolAllowed(
            ManageTodoListTool.name,
            activatedSkillNames: ["demo"],
            enabledSkills: skills
        )
        let defs = [
            ToolDefinition(
                name: "read_text_file",
                description: "r",
                parameters: .schemaObject(properties: [:])
            ),
            ToolDefinition(
                name: "run_shell_command",
                description: "s",
                parameters: .schemaObject(properties: [:])
            ),
            RecallTaskTranscriptTool.definition,
            ManageTodoListTool.definition,
        ]
        let filtered = SkillToolPolicy.filterDefinitions(
            defs,
            activatedSkillNames: ["demo"],
            enabledSkills: skills
        )
        XCTAssertEqual(
            filtered.map(\.name),
            ["read_text_file", RecallTaskTranscriptTool.name, ManageTodoListTool.name]
        )
    }
}
