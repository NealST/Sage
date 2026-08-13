import XCTest
@testable import Sage

final class PathGuardTests: XCTestCase {
    private var fixtureRoot: URL!
    private var projectRoot: URL!
    private var skillDir: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SagePathGuard-\(UUID().uuidString)", isDirectory: true)
        skillDir = fixtureRoot.appendingPathComponent("skill-outside", isDirectory: true)
        let project = fixtureRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "secret".write(
            to: skillDir.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        projectRoot = try PathGuard.validateProjectRoot(project)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testReadAllowlistDoesNotPermitWrites() throws {
        let policy = PathGuard.Policy.project(root: projectRoot)
        let skillFile = skillDir.appendingPathComponent("notes.txt").path
        let allowlisted = skillDir.resolvingSymlinksInPath().path

        try PathGuard.$readAllowlist.withValue([allowlisted]) {
            let readURL = try PathGuard.resolveAllowed(
                skillFile,
                policy: policy,
                access: .read
            )
            XCTAssertEqual(
                readURL.resolvingSymlinksInPath().path,
                URL(fileURLWithPath: skillFile).resolvingSymlinksInPath().path
            )

            XCTAssertThrowsError(
                try PathGuard.resolveAllowed(skillFile, policy: policy, access: .write)
            )
        }
    }

    func testDefaultExplorationPath() throws {
        try PathGuard.$policy.withValue(.project(root: projectRoot)) {
            XCTAssertEqual(try PathGuard.defaultExplorationPath(nil), ".")
            XCTAssertEqual(try PathGuard.defaultExplorationPath("  "), ".")
            XCTAssertEqual(try PathGuard.defaultExplorationPath("src"), "src")
        }
        try PathGuard.$policy.withValue(.home) {
            XCTAssertThrowsError(try PathGuard.defaultExplorationPath(nil))
            XCTAssertEqual(try PathGuard.defaultExplorationPath("~/Documents"), "~/Documents")
        }
    }
}
