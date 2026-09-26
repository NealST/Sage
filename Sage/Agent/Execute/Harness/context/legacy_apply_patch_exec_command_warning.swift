//
//  legacy_apply_patch_exec_command_warning.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/legacy_apply_patch_exec_command_warning.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct LegacyApplyPatchExecCommandWarning: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("legacy.apply_patch_exec_command") }
    public var role: String { "user" }
    public var openMarker: String { "<legacy_apply_patch_exec_command_warning>" }
    public var closeMarker: String { "</legacy_apply_patch_exec_command_warning>" }
    public var body: String {
        "This thread still uses the legacy apply_patch / exec_command tools. Prefer the current shell and apply_patch handlers."
    }
}
