@testable import Sage
import XCTest

final class ProjectAgentsMarkdownTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageAgentsMD-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testMissingFileYieldsEmptySection() {
        XCTAssertNil(ProjectAgentsMarkdown.loadBody(projectRoot: fixtureRoot))
        XCTAssertEqual(ProjectAgentsMarkdown.promptSection(projectRoot: fixtureRoot), "")
    }

    func testLoadsAgentsMarkdownIntoPromptSection() throws {
        let body = "Always run tests before committing."
        try body.write(
            to: fixtureRoot.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(ProjectAgentsMarkdown.loadBody(projectRoot: fixtureRoot), body)
        let section = ProjectAgentsMarkdown.promptSection(projectRoot: fixtureRoot)
        XCTAssertTrue(section.contains("## Project instructions (AGENTS.md)"))
        XCTAssertTrue(section.contains("untrusted project notes"))
        XCTAssertTrue(section.contains(body))
    }

    func testTruncatesOversizedAgentsMarkdown() throws {
        let huge = String(repeating: "a", count: ProjectAgentsMarkdown.maxUTF8Bytes + 200)
        try huge.write(
            to: fixtureRoot.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let loaded = try XCTUnwrap(ProjectAgentsMarkdown.loadBody(projectRoot: fixtureRoot))
        XCTAssertTrue(loaded.contains("truncated"))
        XCTAssertLessThanOrEqual(loaded.utf8.count, ProjectAgentsMarkdown.maxUTF8Bytes + 80)
    }

    func testProjectPromptAppendixIncludesAgentsMarkdown() throws {
        try "Use Swift 6 concurrency.".write(
            to: fixtureRoot.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let project = ProjectRecord(name: "Demo", rootPath: fixtureRoot.path)
        let appendix = SessionLifecycle.projectPromptAppendix(for: project)
        XCTAssertTrue(appendix.contains("Active sandbox"))
        XCTAssertTrue(appendix.contains("AGENTS.md"))
        XCTAssertTrue(appendix.contains("Use Swift 6 concurrency."))
    }
}
