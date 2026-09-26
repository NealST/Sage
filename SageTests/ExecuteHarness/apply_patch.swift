//
//  apply_patch.swift
//  SageTests
//
//  Port of selected codex-rs/core/src/apply_patch_tests.rs cases (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import ApplyPatch
import CodexProtocol
import CodexUtils
@testable import CodexCore
import XCTest

final class CoreApplyPatchTests: XCTestCase {
    func testConvertApplyPatchMapsAddVariant() throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sage-apply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = (dir as NSString).appendingPathComponent("a.txt")
        let pathUri = try PathUri.fromHostNativePath(path)
        let action = ApplyPatchAction.newAddForTest(path: pathUri, content: "hello")
        let got = convertApplyPatchToProtocol(action)
        XCTAssertEqual(got[pathUri.toPathBuf()], .add(content: "hello"))
    }

    func testPrepareApplyPatchAutoApprovesDisabledProfile() throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sage-apply-prep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = (dir as NSString).appendingPathComponent("inside.txt")
        let pathUri = try PathUri.fromHostNativePath(path)
        let action = ApplyPatchAction.newAddForTest(path: pathUri, content: "hello")
        let profile = PermissionProfile.disabled
        let matching = try PatchSandboxRoute.platform(.disabled).prepareMatching(
            configuredPolicy: profile.fileSystemSandboxPolicy(),
            context: FileSystemSandboxPolicyContext(cwd: pathUri, workspaceRoots: [pathUri])
        )
        let prepared = try prepareApplyPatch(
            approvalPolicy: .onRequest,
            permissionProfile: profile,
            matching: matching,
            action: action
        )
        XCTAssertTrue(prepared.autoApproved)
        XCTAssertEqual(
            prepared.execApprovalRequirement,
            .skip(bypassSandbox: false, proposedExecpolicyAmendment: nil)
        )
    }

    func testPrepareApplyPatchAsksUserForReadOnlyOutsideProject() throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sage-apply-ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = (dir as NSString).appendingPathComponent("outside.txt")
        let pathUri = try PathUri.fromHostNativePath(path)
        let workspace = try PathUri.fromHostNativePath(FileManager.default.temporaryDirectory.path)
        let action = ApplyPatchAction.newAddForTest(path: pathUri, content: "hello")
        let profile = PermissionProfile.readOnly()
        let matching = try PatchSandboxRoute.platform(.disabled).prepareMatching(
            configuredPolicy: profile.fileSystemSandboxPolicy(),
            context: FileSystemSandboxPolicyContext(cwd: workspace, workspaceRoots: [workspace])
        )
        let prepared = try prepareApplyPatch(
            approvalPolicy: .onRequest,
            permissionProfile: profile,
            matching: matching,
            action: action
        )
        XCTAssertFalse(prepared.autoApproved)
        guard case .needsApproval = prepared.execApprovalRequirement else {
            return XCTFail("expected needsApproval")
        }
    }
}
