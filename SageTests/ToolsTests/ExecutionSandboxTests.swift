@testable import Sage
import XCTest

final class ExecutionSandboxTests: XCTestCase {
    private var fixtureRoot: URL?

    override func setUpWithError() throws {
        fixtureRoot = nil
    }

    override func tearDownWithError() throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testProfileIsClosedByDefaultAndDeniesNetwork() throws {
        let project = try makeFixture().appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let configuration = ExecutionSandboxConfiguration.shell(
            policy: .project(root: project),
            readAllowlist: [],
            allowsWrites: true,
            allowsNetwork: false
        )

        let profile = ExecutionSandbox.seatbeltProfile(configuration: configuration)

        XCTAssertTrue(profile.contains("(deny default)"))
        XCTAssertFalse(profile.contains("(allow default)"))
        XCTAssertTrue(profile.contains("(deny network*)"))
        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"\(project.path)\"))"))
        XCTAssertTrue(profile.contains("(deny file-write* (subpath \"\(project.path)/.git\"))"))
        XCTAssertTrue(profile.contains("(deny file-write* (regex #\"/\\.git(/|$)\"))"))
    }

    func testExplicitCapabilitiesChangeProfile() throws {
        let project = try makeFixture().appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let configuration = ExecutionSandboxConfiguration.shell(
            policy: .project(root: project),
            readAllowlist: [],
            allowsWrites: true,
            allowsNetwork: true,
            allowsProtectedMetadataWrites: true
        )

        let profile = ExecutionSandbox.seatbeltProfile(configuration: configuration)

        XCTAssertTrue(profile.contains("(allow network*)"))
        XCTAssertFalse(profile.contains("/.git"))
    }

    func testChildEnvironmentDropsImplicitSecretsAndLoaderInjection() {
        let environment = ChildProcessEnvironment.sanitized(overrides: [
            "SAGE_EXPLICIT_SERVER_TOKEN": "allowed-for-explicit-mcp-config",
            "DYLD_INSERT_LIBRARIES": "/tmp/inject.dylib",
            "LD_PRELOAD": "/tmp/inject.so",
        ])

        XCTAssertEqual(environment["SAGE_EXPLICIT_SERVER_TOKEN"], "allowed-for-explicit-mcp-config")
        XCTAssertNil(environment["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(environment["LD_PRELOAD"])
        XCTAssertNotNil(environment["PATH"])
        XCTAssertNotNil(environment["HOME"])
    }

    func testSeatbeltAllowsProjectWorkAndDeniesSiblingRead() async throws {
        let root = try makeFixture()
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.txt")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        let configuration = ExecutionSandboxConfiguration.shell(
            policy: .project(root: project),
            readAllowlist: [],
            allowsWrites: true,
            allowsNetwork: false
        )

        let allowedInvocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-f", "-c", "printf 'ok' > result.txt && cat result.txt"],
            configuration: configuration
        )
        let allowed = try await ProcessRunner.run(
            executable: allowedInvocation.executable,
            arguments: allowedInvocation.arguments,
            currentDirectory: project,
            timeout: .seconds(10)
        )
        XCTAssertEqual(allowed.exitCode, 0, allowed.output)
        XCTAssertEqual(allowed.output, "ok")

        let deniedInvocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-f", "-c", "cat '\(outside.path)'"],
            configuration: configuration
        )
        let denied = try await ProcessRunner.run(
            executable: deniedInvocation.executable,
            arguments: deniedInvocation.arguments,
            currentDirectory: project,
            timeout: .seconds(10)
        )
        XCTAssertNotEqual(denied.exitCode, 0)
        XCTAssertFalse(denied.output.contains("secret"))
    }

    func testMCPProfileCanLaunchFromPathButCannotWriteHome() async throws {
        let root = try makeFixture()
        let input = root.appendingPathComponent("mcp-input.txt")
        try "mcp-ok".write(to: input, atomically: true, encoding: .utf8)
        let configuration = ExecutionSandboxConfiguration.mcpServer()
        let readInvocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["cat", input.path],
            configuration: configuration
        )
        let read = try await ProcessRunner.run(
            executable: readInvocation.executable,
            arguments: readInvocation.arguments,
            currentDirectory: root,
            timeout: .seconds(10)
        )
        XCTAssertEqual(read.exitCode, 0, read.output)
        XCTAssertEqual(read.output, "mcp-ok")

        let destination = root.appendingPathComponent("mcp-write.txt")
        let writeInvocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-f", "-c", "printf blocked > '\(destination.path)'"],
            configuration: configuration
        )
        let write = try await ProcessRunner.run(
            executable: writeInvocation.executable,
            arguments: writeInvocation.arguments,
            currentDirectory: root,
            timeout: .seconds(10)
        )
        XCTAssertNotEqual(write.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testApprovedMCPWriteRootDoesNotOpenSiblingDirectory() async throws {
        let root = try makeFixture()
        let allowedRoot = root.appendingPathComponent("allowed", isDirectory: true)
        let deniedRoot = root.appendingPathComponent("denied", isDirectory: true)
        try FileManager.default.createDirectory(at: allowedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deniedRoot, withIntermediateDirectories: true)
        let configuration = ExecutionSandboxConfiguration.mcpServer(writableRoots: [allowedRoot])
        let invocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-f",
                "-c",
                "printf ok > '\(allowedRoot.path)/ok.txt'; printf blocked > '\(deniedRoot.path)/no.txt'",
            ],
            configuration: configuration
        )
        let result = try await ProcessRunner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            currentDirectory: root,
            timeout: .seconds(10)
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: allowedRoot.appendingPathComponent("ok.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: deniedRoot.appendingPathComponent("no.txt").path))
    }

    func testGeneralShellWriteGrantIsLimitedToWorkingDirectory() async throws {
        let root = try makeFixture()
        let working = root.appendingPathComponent("working", isDirectory: true)
        let sibling = root.appendingPathComponent("sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let configuration = ExecutionSandboxConfiguration.shell(
            policy: .home,
            readAllowlist: [],
            writeRoot: working,
            allowsWrites: true,
            allowsNetwork: false
        )
        let invocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-f",
                "-c",
                "printf ok > local.txt; printf blocked > '\(sibling.path)/outside.txt'",
            ],
            configuration: configuration
        )
        let profile = ExecutionSandbox.seatbeltProfile(configuration: configuration)
        XCTAssertTrue(
            profile.contains("(deny file-write* (subpath \"\(working.path)/.git\"))")
        )

        let result = try await ProcessRunner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            currentDirectory: working,
            timeout: .seconds(10)
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: working.appendingPathComponent("local.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sibling.appendingPathComponent("outside.txt").path))
    }

    func testPathGuardRejectsProtectedMetadataWrites() throws {
        let root = try makeFixture().appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let policy = PathGuard.Policy.project(root: root)

        for relativePath in [".git/config", ".sage/hooks.json", ".agents/policy.json"] {
            XCTAssertThrowsError(
                try PathGuard.resolveAllowed(relativePath, policy: policy, access: .write)
            )
            XCTAssertNoThrow(
                try PathGuard.resolveAllowed(relativePath, policy: policy, access: .read)
            )
        }
    }

    private func makeFixture() throws -> URL {
        if let fixtureRoot {
            return fixtureRoot
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Caches/SageExecutionSandbox-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fixtureRoot = root
        return root
    }
}
