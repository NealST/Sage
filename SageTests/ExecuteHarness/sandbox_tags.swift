//
//  sandbox_tags.swift
//  SageTests
//
//  Port of codex-rs/core/src/sandbox_tags.rs tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import FileSystem
@testable import Sage
import XCTest

final class SandboxTagsTests: XCTestCase {
    func testDisabledProfileLabels() {
        let tags = SandboxTags(
            profile: .disabled,
            cwd: FileManager.default.currentDirectoryPath,
            windowsSandboxSelection: .disabled,
            enforceManagedNetwork: false
        )
        XCTAssertEqual(tags.sandbox, "none")
        XCTAssertEqual(tags.policy, "danger-full-access")
    }

    func testReadOnlyManagedProfile() {
        let tags = SandboxTags(
            profile: .readOnly(),
            cwd: FileManager.default.currentDirectoryPath,
            windowsSandboxSelection: .disabled,
            enforceManagedNetwork: false
        )
        XCTAssertEqual(tags.policy, "read-only")
        XCTAssertEqual(tags.sandbox, "seatbelt")
    }
}
