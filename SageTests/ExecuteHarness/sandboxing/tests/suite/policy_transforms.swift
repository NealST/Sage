//
//  policy_transforms.swift
//  SageTests
//
//  Port of focused cases from
//  codex-rs/sandboxing/src/policy_transforms.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
@testable import CodexSandboxing
import CodexUtils
import XCTest

final class PolicyTransformsTests: XCTestCase {
    func testNormalizeRejectsNonDenyGlob() {
        let profile = AdditionalPermissionProfile(
            fileSystem: FileSystemPermissions(entries: [
                .new(.globPattern(pattern: "secrets/**"), .read)
            ]))
        XCTAssertThrowsError(try normalizeAdditionalPermissions(profile))
    }

    func testMaterializePreservesPathGrant() throws {
        let cwd = try PathUri.parse("file:///tmp/project")
        let context = FileSystemSandboxPolicyContext(cwd: cwd, workspaceRoots: [cwd])
        let grant = try PathUri.parse("file:///tmp/project/src")
        let profile = AdditionalPermissionProfile(
            fileSystem: FileSystemPermissions(entries: [
                .new(.path(path: grant), .write)
            ]))
        let materialized = try materializeAdditionalPermissionsWithContext(profile, context: context)
        XCTAssertEqual(materialized.fileSystem?.entries.count, 1)
        XCTAssertEqual(materialized.fileSystem?.entries.first?.access, .write)
    }

    func testIntersectKeepsOverlappingGrant() throws {
        let cwd = try PathUri.parse("file:///tmp/project")
        let context = FileSystemSandboxPolicyContext(cwd: cwd, workspaceRoots: [cwd])
        let src = try PathUri.parse("file:///tmp/project/src")
        let requested = AdditionalPermissionProfile(
            fileSystem: FileSystemPermissions(entries: [
                .new(.path(path: src), .write)
            ]))
        let granted = requested
        let intersection = intersectPermissionProfilesWithContext(
            requested: requested, granted: granted, context: context)
        XCTAssertEqual(intersection.fileSystem?.entries.first?.access, .write)
    }

    func testIntersectNetworkRequiresBothEnabled() {
        let cwd = try! PathUri.parse("file:///tmp/project")
        let context = FileSystemSandboxPolicyContext(cwd: cwd, workspaceRoots: [cwd])
        let requested = AdditionalPermissionProfile(network: NetworkPermissions(enabled: true))
        let granted = AdditionalPermissionProfile(network: NetworkPermissions(enabled: true))
        let both = intersectPermissionProfilesWithContext(
            requested: requested, granted: granted, context: context)
        XCTAssertEqual(both.network?.enabled, true)

        let denied = intersectPermissionProfilesWithContext(
            requested: requested,
            granted: AdditionalPermissionProfile(),
            context: context)
        XCTAssertNil(denied.network)
    }

    func testMergePrefersEnabledNetwork() {
        let merged = mergePermissionProfiles(
            base: AdditionalPermissionProfile(network: NetworkPermissions(enabled: true)),
            permissions: AdditionalPermissionProfile())
        XCTAssertEqual(merged?.network?.enabled, true)
    }
}
