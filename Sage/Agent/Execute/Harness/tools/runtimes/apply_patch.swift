//
//  apply_patch.swift
//  ToolsRuntimes
//
//  Port of codex-rs/core/src/tools/runtimes/apply_patch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Applies an already-parsed patch in-process. Approval, PathGuard, and the
//  diff payload stay in tools/handlers/apply_patch.swift.
//

import ApplyPatch
import Foundation

public struct ApplyPatchRequest {
    public var cwd: URL
    public var hunks: [Hunk]
    public var options: ApplyPatchOptions

    public init(cwd: URL, hunks: [Hunk], options: ApplyPatchOptions) {
        self.cwd = cwd
        self.hunks = hunks
        self.options = options
    }
}

public enum ApplyPatchRuntime {
    public static func run(_ request: ApplyPatchRequest) throws -> (delta: AppliedPatchDelta, summary: String) {
        try applyHunks(
            request.hunks,
            cwd: request.cwd,
            options: request.options
        )
    }
}
