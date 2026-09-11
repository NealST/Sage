@testable import Sage
import XCTest

final class SeatbeltSandboxTests: XCTestCase {
    // MARK: - Profile mapping

    func testHomeProfileWritesHomeAndKeepsItReadable() {
        let profile = SeatbeltSandbox.profile(for: .home, readAllowlist: [])
        XCTAssertEqual(profile.writableRoots, [PathGuard.resolvedHomePath])
        XCTAssertTrue(profile.readableRoots.isEmpty)
        XCTAssertFalse(profile.deniesHomeReads)
        XCTAssertFalse(profile.skipsShellStartupFiles)
    }

    func testProjectProfileDeniesHomeAndReallowsRoots() {
        let root = URL(fileURLWithPath: "/tmp/sage-proj")
        let profile = SeatbeltSandbox.profile(
            for: .project(root: root),
            readAllowlist: ["/tmp/skill-dir"],
        )
        XCTAssertEqual(profile.writableRoots, ["/tmp/sage-proj"])
        XCTAssertEqual(profile.readableRoots, ["/tmp/sage-proj", "/tmp/skill-dir"])
        XCTAssertTrue(profile.deniesHomeReads)
        XCTAssertTrue(profile.skipsShellStartupFiles)
    }

    // MARK: - Rendering

    func testRenderReferencesParamsWithoutInterpolatingPaths() {
        let profile = SeatbeltSandbox.Profile(
            homePath: "/tmp/fake-home",
            readableRoots: ["/tmp/fake-home/proj"],
            writableRoots: ["/tmp/fake-home/proj"],
            deniesHomeReads: true,
            skipsShellStartupFiles: true,
        )
        let rendered = SeatbeltSandbox.render(profile)
        XCTAssertFalse(rendered.text.contains("/tmp/fake-home"))
        XCTAssertTrue(rendered.text.contains(#"(param "HOME")"#))
        XCTAssertTrue(rendered.text.contains(#"(param "READABLE_ROOT_0")"#))
        XCTAssertTrue(rendered.text.contains(#"(param "WRITABLE_ROOT_0")"#))
        XCTAssertEqual(
            rendered.parameters.map(\.value),
            ["/tmp/fake-home", "/tmp/fake-home/proj", "/tmp/fake-home/proj"],
        )
    }

    func testRenderKeepsWritableAnchorDeniesLast() {
        let profile = SeatbeltSandbox.Profile(
            homePath: "/tmp/fake-home",
            readableRoots: [],
            writableRoots: ["/tmp/fake-home/proj"],
            deniesHomeReads: false,
            skipsShellStartupFiles: false,
        )
        let rendered = SeatbeltSandbox.render(profile)
        let allowRange = rendered.text.range(of: #"(allow file-write* (subpath (param "WRITABLE_ROOT_0")))"#)
        let denyRange = rendered.text.range(of: "(deny file-write-unlink")
        XCTAssertNotNil(allowRange)
        XCTAssertNotNil(denyRange)
        if let allowRange, let denyRange {
            XCTAssertTrue(allowRange.upperBound <= denyRange.lowerBound)
        }
    }

    // MARK: - Functional (kernel-enforced; skipped without sandbox-exec)

    func testSandboxedWriteInsideRootSucceeds() async throws {
        try XCTSkipUnless(SeatbeltSandbox.isAvailable)
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try await runSandboxed(
            "echo hi > made.txt && cat made.txt",
            in: fixture.appendingPathComponent("proj"),
            profile: projectProfile(fixture: fixture),
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("hi"))
    }

    func testSandboxedHomeReadDeniedInProjectMode() async throws {
        try XCTSkipUnless(SeatbeltSandbox.isAvailable)
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try await runSandboxed(
            "cat \"\(fixture.path)/home/secret.txt\"",
            in: fixture.appendingPathComponent("proj"),
            profile: projectProfile(fixture: fixture),
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.output.contains("s3cret"))
    }

    func testSandboxedHomeWriteDeniedInProjectMode() async throws {
        try XCTSkipUnless(SeatbeltSandbox.isAvailable)
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try await runSandboxed(
            "echo no > \"\(fixture.path)/home/blocked.txt\"",
            in: fixture.appendingPathComponent("proj"),
            profile: projectProfile(fixture: fixture),
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.appendingPathComponent("home/blocked.txt").path
            )
        )
    }

    func testSandboxedSystemBinaryExecutes() async throws {
        try XCTSkipUnless(SeatbeltSandbox.isAvailable)
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try await runSandboxed(
            "/usr/bin/true && /usr/bin/git --version",
            in: fixture.appendingPathComponent("proj"),
            profile: projectProfile(fixture: fixture),
        )
        XCTAssertEqual(result.exitCode, 0)
    }

    func testSandboxedReadOutsideHomeStillWorks() async throws {
        try XCTSkipUnless(SeatbeltSandbox.isAvailable)
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try await runSandboxed(
            "head -1 /etc/hosts",
            in: fixture.appendingPathComponent("proj"),
            profile: projectProfile(fixture: fixture),
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.output.isEmpty)
    }

    func testSandboxMarkerVisibleToChildProcess() async throws {
        try XCTSkipUnless(SeatbeltSandbox.isAvailable)
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let result = try await runSandboxed(
            "echo $\(SeatbeltSandbox.environmentMarkerKey)",
            in: fixture.appendingPathComponent("proj"),
            profile: projectProfile(fixture: fixture),
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains(SeatbeltSandbox.environmentMarkerValue))
    }

    // MARK: - Helpers

    /// Fixture tree under a hidden dir in the real home: home/secret.txt + proj/ok.txt.
    /// Must live under home (not /tmp): the base policy allows /tmp writes, which
    /// would mask the home-write denial this suite verifies.
    private func makeFixture() throws -> URL {
        let fixture = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sage-seatbelt-tests-\(UUID().uuidString)")
        let home = fixture.appendingPathComponent("home")
        let project = fixture.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "s3cret".write(to: home.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try "ok".write(to: project.appendingPathComponent("ok.txt"), atomically: true, encoding: .utf8)
        return fixture
    }

    private func projectProfile(fixture: URL) -> SeatbeltSandbox.Profile {
        SeatbeltSandbox.Profile(
            homePath: fixture.appendingPathComponent("home").path,
            readableRoots: [fixture.appendingPathComponent("proj").path],
            writableRoots: [fixture.appendingPathComponent("proj").path],
            deniesHomeReads: true,
            skipsShellStartupFiles: true,
        )
    }

    private func runSandboxed(
        _ command: String,
        in workingDirectory: URL,
        profile: SeatbeltSandbox.Profile
    ) async throws -> ProcessRunResult {
        let invocation = SeatbeltSandbox.invocation(command: command, profile: profile)
        return try await ProcessRunner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            currentDirectory: workingDirectory,
            timeout: .seconds(15),
            environment: invocation.environment ?? ChildProcessEnvironment.sanitized(),
        )
    }
}
