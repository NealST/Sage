//
//  shell_snapshot.swift
//  SageTests
//
//  Port of selected shell-snapshot cases from
//  codex-rs/core/src/shell_snapshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import CodexUtils
@testable import CodexCore
import XCTest

final class CoreShellSnapshotTests: XCTestCase {
    func testDisabledSnapshotDoesNotBuild() async {
        let snapshot = ShellSnapshot.disabled()
        XCTAssertFalse(snapshot.shouldRebuildInherited())
        let built = await snapshot.build(
            cwd: PathUri.fromAbsPath(try! AbsolutePathBuf.fromAbsolutePath("/tmp")),
            shell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
            allowLoginShell: true,
            sandbox: nil
        )
        XCTAssertNil(built)
    }

    func testSnapshotReadPermissionsSkipWhenReadable() throws {
        let cwd = try AbsolutePathBuf.fromAbsolutePath("/tmp")
        let snapshotPath = cwd.join("snap.sh")
        let profile = PermissionProfile.disabled
        XCTAssertNil(
            snapshotReadPermissions(
                snapshotPath: snapshotPath,
                permissions: profile,
                sandboxCwd: PathUri.fromAbsPath(cwd)
            )
        )
    }

    func testLocalSnapshotCaptureWritesFile() async throws {
        let home = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sage-snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let codexHome = try AbsolutePathBuf.fromAbsolutePath(home)
        let snapshot = ShellSnapshot(codexHome: codexHome, sessionId: ThreadId())
        let built = await snapshot.build(
            cwd: PathUri.fromAbsPath(codexHome),
            shell: Shell(shellType: .sh, shellPath: "/bin/sh"),
            allowLoginShell: true,
            sandbox: nil
        )
        XCTAssertNotNil(built)
        if let path = built?.path.asPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(contents.isEmpty)
        }
    }
}
