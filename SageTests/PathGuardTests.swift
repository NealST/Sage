@testable import Sage
import XCTest

final class PathGuardTests: XCTestCase {
    private var fixtureRoot: URL!
    private var projectRoot: URL!
    private var skillDir: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Caches/SagePathGuard-\(UUID().uuidString)",
                isDirectory: true
            )
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

    func testDisplayPathProjectRelative() throws {
        let nested = projectRoot.appendingPathComponent("src/App.swift")
        try FileManager.default.createDirectory(
            at: nested.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "ok".write(to: nested, atomically: true, encoding: .utf8)

        let policy = PathGuard.Policy.project(root: projectRoot)
        XCTAssertEqual(PathGuard.displayPath(projectRoot.path, policy: policy), ".")
        XCTAssertEqual(PathGuard.displayPath(nested.path, policy: policy), "src/App.swift")
        XCTAssertEqual(
            PathGuard.displayPath("src/App.swift", policy: policy),
            "src/App.swift"
        )

        let homeFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("SagePathGuardDisplay-\(UUID().uuidString).txt")
        // Outside project → tilde form (file need not exist for display formatting).
        let outside = skillDir.appendingPathComponent("notes.txt")
        let displayed = PathGuard.displayPath(outside.path, policy: policy)
        XCTAssertFalse(displayed.hasPrefix(projectRoot.path))
        XCTAssertTrue(displayed.hasPrefix("~") || displayed.hasPrefix("/"))
        _ = homeFile
    }

    func testDisplayPathHomeTilde() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let docs = home.appendingPathComponent("Documents")
        XCTAssertEqual(PathGuard.displayPath(home.path, policy: .home), "~")
        XCTAssertEqual(
            PathGuard.displayPath(docs.path, policy: .home),
            "~/Documents"
        )
    }

    func testFileURLForDisplayPath() throws {
        let nested = projectRoot.appendingPathComponent("readme.md")
        try "hi".write(to: nested, atomically: true, encoding: .utf8)
        let policy = PathGuard.Policy.project(root: projectRoot)

        let fromRelative = PathGuard.fileURL(forDisplayPath: "readme.md", policy: policy)
        XCTAssertEqual(
            fromRelative?.resolvingSymlinksInPath().path,
            nested.resolvingSymlinksInPath().path
        )

        let fromAbsolute = PathGuard.fileURL(forDisplayPath: nested.path, policy: policy)
        XCTAssertEqual(
            fromAbsolute?.resolvingSymlinksInPath().path,
            nested.resolvingSymlinksInPath().path
        )
    }

    func testEnumeratedSymlinkOutsideProjectIsSkipped() throws {
        let leak = projectRoot.appendingPathComponent("leak")
        try FileManager.default.createSymbolicLink(
            at: leak,
            withDestinationURL: skillDir
        )
        let inside = projectRoot.appendingPathComponent("ok.txt")
        try "ok".write(to: inside, atomically: true, encoding: .utf8)

        PathGuard.$policy.withValue(.project(root: projectRoot)) {
            XCTAssertNil(PathGuard.resolveEnumeratedURL(leak, access: .read))
            XCTAssertNotNil(PathGuard.resolveEnumeratedURL(inside, access: .read))
        }
    }

    func testEnumeratedInProjectFileResolves() throws {
        let inside = projectRoot.appendingPathComponent("notes.txt")
        try "hi".write(to: inside, atomically: true, encoding: .utf8)
        try PathGuard.$policy.withValue(.project(root: projectRoot)) {
            let resolved = try XCTUnwrap(PathGuard.resolveEnumeratedURL(inside, access: .read))
            XCTAssertEqual(
                resolved.resolvingSymlinksInPath().path,
                inside.resolvingSymlinksInPath().path
            )
        }
    }
}
