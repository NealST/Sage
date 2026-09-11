@testable import Sage
import XCTest

final class GitBranchReaderTests: XCTestCase {
    private var repoRoot: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-git-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        repoRoot = dir
        try runGit(["init"])
        try runGit(["config", "user.email", "test@sage.local"])
        try runGit(["config", "user.name", "Sage Test"])
    }

    override func tearDownWithError() throws {
        if let repoRoot {
            try? FileManager.default.removeItem(at: repoRoot)
        }
    }

    // MARK: - recentCommits

    func testRecentCommitsParsesDateAuthorAndSubject() throws {
        try write("first.txt", content: "one")
        try commit(date: "2026-01-01", subject: "Add project files")
        try write("second.txt", content: "two")
        try commit(date: "2026-01-02", subject: "Fix\ttabbed subject")

        let commits = GitBranchReader.recentCommits(inProjectRoot: repoRoot)
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].subject, "Fix\ttabbed subject")
        XCTAssertEqual(commits[0].date, "2026-01-02")
        XCTAssertEqual(commits[0].author, "Sage Test")
        XCTAssertEqual(commits[1].subject, "Add project files")
        XCTAssertEqual(commits[1].date, "2026-01-01")
        XCTAssertFalse(commits[0].shortHash.isEmpty)
        XCTAssertGreaterThan(commits[0].fullHash.count, commits[0].shortHash.count)
        XCTAssertTrue(commits[0].fullHash.hasPrefix(commits[0].shortHash))
        XCTAssertEqual(Set(commits.map(\.fullHash)).count, 2)
    }

    func testCommitCountTracksHistoryAndIsNilWhenUnborn() throws {
        XCTAssertNil(GitBranchReader.commitCount(inProjectRoot: repoRoot))
        try write("initial.txt", content: "one")
        try commit(date: "2026-01-01", subject: "Initial")
        XCTAssertEqual(GitBranchReader.commitCount(inProjectRoot: repoRoot), 1)
    }

    // MARK: - workingTreeStatus

    func testWorkingTreeStatusClassifiesChanges() throws {
        try write("tracked.txt", content: "one")
        try write("gone.txt", content: "will delete")
        try commit(date: "2026-01-01", subject: "Initial")

        try write("tracked.txt", content: "changed")
        try? FileManager.default.removeItem(at: repoRoot.appendingPathComponent("gone.txt"))
        try write("staged-new.txt", content: "staged")
        try runGit(["add", "staged-new.txt"])
        try write("loose-new.txt", content: "untracked")

        let status = try XCTUnwrap(GitBranchReader.workingTreeStatus(inProjectRoot: repoRoot))
        XCTAssertEqual(status.counts.modified, 1)
        XCTAssertEqual(status.counts.deleted, 1)
        XCTAssertEqual(status.counts.added, 1)
        XCTAssertEqual(status.counts.untracked, 1)
        XCTAssertFalse(status.isClean)
        XCTAssertEqual(status.pathStatuses["tracked.txt"], "M")
        XCTAssertEqual(status.pathStatuses["gone.txt"], "D")
        XCTAssertEqual(status.pathStatuses["staged-new.txt"], "A")
        XCTAssertEqual(status.pathStatuses["loose-new.txt"], "?")
    }

    func testWorkingTreeStatusSkipsRenameSourceRecord() throws {
        try write("old.txt", content: "one")
        try commit(date: "2026-01-01", subject: "Initial")
        try runGit(["mv", "old.txt", "new.txt"])

        let status = try XCTUnwrap(GitBranchReader.workingTreeStatus(inProjectRoot: repoRoot))
        XCTAssertEqual(status.counts.modified, 1)
        XCTAssertEqual(status.counts.added + status.counts.deleted + status.counts.untracked, 0)
        XCTAssertEqual(status.pathStatuses["new.txt"], "M")
        XCTAssertNil(status.pathStatuses["old.txt"])
    }

    func testStatusLetterMarksDirectoriesContainingChanges() throws {
        try write("docs/readme.md", content: "one")
        try commit(date: "2026-01-01", subject: "Initial")
        try write("docs/readme.md", content: "changed")
        try write("docs/extra.md", content: "new")

        let status = try XCTUnwrap(GitBranchReader.workingTreeStatus(inProjectRoot: repoRoot))
        XCTAssertEqual(status.statusLetter(containedInDirectory: "docs"), "M")
        XCTAssertNil(status.statusLetter(containedInDirectory: "other"))
    }

    func testWorkingTreeStatusIsCleanAfterCommit() throws {
        try write("tracked.txt", content: "one")
        try commit(date: "2026-01-01", subject: "Initial")

        let status = try XCTUnwrap(GitBranchReader.workingTreeStatus(inProjectRoot: repoRoot))
        XCTAssertTrue(status.isClean)
    }

    // MARK: - Helpers

    private func commit(date: String, subject: String) throws {
        let dates = [
            "GIT_AUTHOR_DATE": "\(date)T12:00:00 +0000",
            "GIT_COMMITTER_DATE": "\(date)T12:00:00 +0000",
        ]
        try runGit(["add", "-A"], env: dates)
        try runGit(["commit", "-m", subject, "--no-gpg-sign"], env: dates)
    }

    private func write(_ relativePath: String, content: String) throws {
        let url = repoRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runGit(_ arguments: [String], env: [String: String] = [:]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoRoot.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0] = $1 }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments) failed")
    }
}
