//
//  permissions.swift
//  SageTests
//
//  Port of key cases from codex-rs/protocol/src/permissions.rs and
//  permission_profile_snapshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//

import Foundation
@testable import CodexProtocol
import CodexUtils
import XCTest

final class PermissionsTests: XCTestCase {
    func testAccessModePrecedence() {
        XCTAssertTrue(FileSystemAccessMode.deny > .write)
        XCTAssertTrue(FileSystemAccessMode.write > .read)
        XCTAssertTrue(FileSystemAccessMode.read.canRead())
        XCTAssertFalse(FileSystemAccessMode.deny.canRead())
        XCTAssertTrue(FileSystemAccessMode.write.canWrite())
        XCTAssertFalse(FileSystemAccessMode.read.canWrite())
    }

    func testAccessModeNoneAliasDecodesAsDeny() throws {
        let data = Data("\"none\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(FileSystemAccessMode.self, from: data), .deny)
        let encoded = try JSONEncoder().encode(FileSystemAccessMode.deny)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"deny\"")
    }

    func testSandboxPolicyMapsToFileSystemSandboxPolicy() {
        let readOnly = FileSystemSandboxPolicy(SandboxPolicy.newReadOnlyPolicy())
        XCTAssertEqual(readOnly.kind, .restricted)
        XCTAssertEqual(readOnly.entries.count, 1)
        XCTAssertEqual(readOnly.entries[0].path, .special(value: .root))
        XCTAssertEqual(readOnly.entries[0].access, .read)

        let danger = FileSystemSandboxPolicy(.dangerFullAccess)
        XCTAssertEqual(danger, .unrestricted())

        let workspace = FileSystemSandboxPolicy(SandboxPolicy.newWorkspaceWritePolicy())
        XCTAssertEqual(workspace.kind, .restricted)
        XCTAssertTrue(workspace.entries.contains {
            $0.path == .special(value: .root) && $0.access == .read
        })
        XCTAssertTrue(workspace.entries.contains {
            $0.path == .special(value: .projectRoots(subpath: nil)) && $0.access == .write
        })
    }

    func testCanReadPathAndCanWritePathOnRestrictedPolicy() throws {
        let cwd = try PathUri.parse("file:///workspace")
        let privateDir = try PathUri.parse("file:///workspace/private")
        let outside = try PathUri.parse("file:///outside")
        let context = FileSystemSandboxPolicyContext(
            cwd: cwd,
            workspaceRoots: [cwd],
            userHomeDir: nil,
            temporaryDirectories: nil
        )
        let policy = FileSystemSandboxPolicy.restricted([
            FileSystemSandboxEntry.new(.special(value: .root), .read),
            FileSystemSandboxEntry.new(.path(path: cwd), .write),
            FileSystemSandboxEntry.new(.path(path: privateDir), .deny),
        ])
        XCTAssertTrue(policy.canReadPath(cwd, context: context))
        XCTAssertTrue(policy.canWritePath(cwd, context: context))
        XCTAssertTrue(policy.canReadPath(outside, context: context))
        XCTAssertFalse(policy.canWritePath(outside, context: context))
        XCTAssertFalse(policy.canReadPath(privateDir, context: context))
        XCTAssertFalse(policy.canWritePath(privateDir, context: context))
    }

    func testDenyReadValidatorMissingRequiredDeny() throws {
        let cwd = try PathUri.parse("file:///workspace")
        let context = FileSystemSandboxPolicyContext(
            cwd: cwd,
            workspaceRoots: [cwd]
        )
        let required = FileSystemSandboxPolicy.restricted([
            FileSystemSandboxEntry.new(.special(value: .root), .read),
            FileSystemSandboxEntry.new(.path(path: try PathUri.parse("file:///workspace/secret")), .deny),
        ])
        let selected = FileSystemSandboxPolicy.restricted([
            FileSystemSandboxEntry.new(.special(value: .root), .read),
        ])
        let validator = try DenyReadValidator(required: required, context: context)
        XCTAssertThrowsError(try validator.validate(selected, context: context)) { error in
            XCTAssertEqual(error as? DenyReadViolation, .missingRequiredDeny)
        }
    }

    func testSnapshotLegacyAndActiveConstructors() {
        let profile = PermissionProfile.readOnly()
        let legacy = PermissionProfileSnapshot.legacy(profile)
        XCTAssertEqual(legacy.permissionProfile(), profile)
        XCTAssertNil(legacy.activePermissionProfile())
        XCTAssertTrue(legacy.profileWorkspaceRoots().isEmpty)

        let active = PermissionProfileSnapshot.active(profile, .readOnly())
        XCTAssertEqual(active.permissionProfile(), profile)
        XCTAssertEqual(active.activePermissionProfile()?.id, builtInPermissionProfileReadOnly)
        XCTAssertEqual(
            PermissionProfileSnapshot.fromSessionSnapshot(profile, nil),
            legacy
        )
        XCTAssertEqual(
            PermissionProfileSnapshot.fromSessionSnapshot(profile, .readOnly()),
            active
        )
    }

    func testNetworkSandboxPolicyFromSandboxPolicy() {
        XCTAssertTrue(NetworkSandboxPolicy(.dangerFullAccess).isEnabled)
        XCTAssertFalse(NetworkSandboxPolicy(SandboxPolicy.newReadOnlyPolicy()).isEnabled)
    }

    func testProtectedMetadataHelpers() {
        XCTAssertTrue(isProtectedMetadataName(".git"))
        XCTAssertTrue(isProtectedMetadataName(".codex"))
        XCTAssertFalse(isProtectedMetadataName("src"))
        XCTAssertEqual(PROTECTED_METADATA_PATH_NAMES, [".git", ".agents", ".codex"])
    }
}
