//
//  permission_profile_intersection.swift
//  SageTests
//
//  Port of key cases from
//  codex-rs/protocol/src/permission_profile_intersection_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//

import Foundation
@testable import CodexProtocol
import CodexUtils
import XCTest

final class PermissionProfileIntersectionTests: XCTestCase {
    private func absolute(_ path: String) throws -> AbsolutePathBuf {
        try AbsolutePathBuf.fromAbsolutePath(path)
    }

    private func managed(_ entries: [FileSystemSandboxEntry]) -> PermissionProfile {
        .fromRuntimePermissions(.restricted(entries), .restricted)
    }

    private func special(
        _ value: FileSystemSpecialPath,
        _ access: FileSystemAccessMode
    ) -> FileSystemSandboxEntry {
        .new(.special(value: value), access)
    }

    func testIdenticalUnrestrictedAndDisabledProfilesKeepExistingEnforcement() throws {
        let root = try absolute(FileManager.default.temporaryDirectory.path)
        let readonly = PermissionProfile.readOnly()
        let disabled = PermissionProfile.disabled
        XCTAssertEqual(
            try intersectEffectivePermissionProfiles(disabled, readonly, cwd: root.asPath),
            readonly
        )
        XCTAssertEqual(
            try intersectEffectivePermissionProfiles(readonly, disabled, cwd: root.asPath),
            readonly
        )
        XCTAssertEqual(
            try intersectEffectivePermissionProfiles(disabled, disabled, cwd: root.asPath),
            disabled
        )
        let unrestricted = PermissionProfile.fromRuntimePermissions(.unrestricted(), .enabled)
        XCTAssertEqual(
            try intersectEffectivePermissionProfiles(unrestricted, readonly, cwd: root.asPath),
            readonly
        )

        let minimal = managed([special(.minimal, .read)])
        XCTAssertEqual(
            try intersectEffectivePermissionProfiles(minimal, minimal, cwd: root.asPath),
            minimal
        )
    }

    func testUnsupportedUnresolvedAndOptionalPolicyShapesFailClosed() throws {
        let root = try absolute(FileManager.default.temporaryDirectory.path)
        let readonly = PermissionProfile.readOnly()
        let external = PermissionProfile.external(network: .enabled)
        for pair in [(external, readonly), (readonly, external)] {
            XCTAssertThrowsError(
                try intersectEffectivePermissionProfiles(pair.0, pair.1, cwd: root.asPath)
            ) { error in
                XCTAssertEqual(error as? PermissionIntersectionError, .externalSandbox)
            }
        }

        let unmaterialized = PermissionProfile.workspaceWrite()
        XCTAssertThrowsError(
            try intersectEffectivePermissionProfiles(unmaterialized, readonly, cwd: root.asPath)
        ) { error in
            guard case .unsupportedPath = error as? PermissionIntersectionError else {
                return XCTFail("expected unsupported path, got \(error)")
            }
        }

        let minimal = managed([special(.minimal, .read)])
        XCTAssertThrowsError(
            try intersectEffectivePermissionProfiles(minimal, readonly, cwd: root.asPath)
        ) { error in
            XCTAssertEqual(error as? PermissionIntersectionError, .platformDefaults)
        }

        XCTAssertThrowsError(
            try intersectEffectivePermissionProfiles(
                readonly, readonly, cwd: "relative/workspace")
        ) { error in
            guard case .unsupportedPath = error as? PermissionIntersectionError else {
                return XCTFail("expected unsupported path, got \(error)")
            }
        }
    }

    func testExactDeniesNestedReadCarveoutsAndReopenedWritesArePreserved() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-intersect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = try AbsolutePathBuf.fromAbsolutePath(temp.path).canonicalize()
        let shared = root.join("shared")
        let editable = shared.join("editable")
        let leftSecret = root.join("left-secret.env")
        let rightSecret = root.join("right-secret.token")
        for directory in [editable, leftSecret, rightSecret] {
            try FileManager.default.createDirectory(
                atPath: directory.asPath, withIntermediateDirectories: true)
        }

        func entry(_ path: AbsolutePathBuf, _ access: FileSystemAccessMode) -> FileSystemSandboxEntry {
            .new(FileSystemPath(path), access)
        }
        func denyGlob(_ pattern: String) -> FileSystemSandboxEntry {
            .new(.globPattern(pattern: pattern), .deny)
        }
        func rooted(
            _ access: FileSystemAccessMode,
            _ extra: [FileSystemSandboxEntry]
        ) -> PermissionProfile {
            var entries = [
                FileSystemSandboxPolicy.readOnly().entries[0],
                entry(root, access),
            ]
            entries.append(contentsOf: extra)
            return managed(entries)
        }

        var leftPolicy = rooted(.write, [
            entry(shared, .read),
            entry(editable, .write),
            entry(leftSecret, .deny),
            denyGlob("**/*.env"),
        ]).fileSystemSandboxPolicy()
        leftPolicy.globScanMaxDepth = 2
        let left = PermissionProfile.fromRuntimePermissions(leftPolicy, .restricted)

        var rightPolicy = rooted(.write, [
            entry(shared, .write),
            entry(editable, .write),
            entry(rightSecret, .deny),
            denyGlob("**/*.token"),
        ]).fileSystemSandboxPolicy()
        rightPolicy.globScanMaxDepth = 4
        let right = PermissionProfile.fromRuntimePermissions(rightPolicy, .restricted)

        let result = try intersectEffectivePermissionProfiles(left, right, cwd: root.asPath)
        let policy = result.fileSystemSandboxPolicy()
        let denies = try XCTUnwrap(
            try ReadDenyMatcher.tryNewForLocalPaths(policy, cwd: root.asPath))
        XCTAssertEqual(
            [root, shared, editable].map {
                policy.resolveAccessForLocalPathWithCwd($0.asPath, cwd: root.asPath)
            },
            [.write, .read, .write]
        )
        XCTAssertEqual(
            [leftSecret, rightSecret, root.join("credentials.env"), root.join("credentials.token")]
                .map { denies.isLocalPathReadDenied($0.asPath) },
            [true, true, true, true]
        )
        XCTAssertEqual(policy.globScanMaxDepth, 4)
        XCTAssertTrue(policy.entries.contains(entry(leftSecret, .deny)))
        XCTAssertEqual(
            try intersectEffectivePermissionProfiles(right, left, cwd: root.asPath),
            result
        )
        let unbounded = rooted(.write, [denyGlob("**/*.key")])
        XCTAssertNil(
            try intersectEffectivePermissionProfiles(left, unbounded, cwd: root.asPath)
                .fileSystemSandboxPolicy()
                .globScanMaxDepth
        )
    }
}
