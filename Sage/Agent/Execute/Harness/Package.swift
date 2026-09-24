// swift-tools-version: 6.0
//
// Execute harness modules. Source paths match the Codex tree so a Codex file
// and its Swift port stay side by side (EXECUTE_HARNESS_PORT_PLAN.md §5):
//
//   codex-rs/protocol/src/<file>.rs
//     → protocol/src/<file>.swift             module CodexProtocol
//   codex-rs/file-system/src/lib.rs
//     → file-system/src/lib.swift             module FileSystem
//   codex-rs/apply-patch/src/<file>.rs
//     → apply-patch/src/<file>.swift          module ApplyPatch
//   codex-rs/core/src/tools/runtimes/<file>.rs
//     → tools/runtimes/<file>.swift           module ToolsRuntimes
//
// `tools/handlers`, `tools/*.swift`, `session`, and `tasks` stay in the Sage
// app module. They close over Sage session types (PathGuard, AgentTool,
// TurnCoordinator). Codex keeps those in one core crate too; Swift splits a
// module only where a second file must reuse a Codex name (`apply_patch`).
//
// Per-file port state is tracked in PORTING.md (scripts/harness_port.py).

import PackageDescription

let package = Package(
    name: "ExecuteHarness",
    // .v15: CodexProtocol uses UInt128 (ThreadId.init(u128:)), available macOS 15+.
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CodexProtocol", targets: ["CodexProtocol"]),
        .library(name: "CodexUtils", targets: ["CodexUtils"]),
        .library(name: "CodexAsyncUtils", targets: ["CodexAsyncUtils"]),
        .library(name: "FileSystem", targets: ["FileSystem"]),
        .library(name: "ApplyPatch", targets: ["ApplyPatch"]),
        .library(name: "ToolsRuntimes", targets: ["ToolsRuntimes"]),
    ],
    targets: [
        .target(
            name: "CodexProtocol",
            path: "protocol/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // All codex-rs/utils/* crates compile into one module (plan §4.1).
        .target(
            name: "CodexUtils",
            path: "utils",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/async-utils — separate module because an SPM target has a
        // single path and async-utils/ is not under utils/ (plan §4.1 note).
        .target(
            name: "CodexAsyncUtils",
            path: "async-utils/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "FileSystem",
            path: "file-system/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ApplyPatch",
            dependencies: ["FileSystem"],
            path: "apply-patch/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ToolsRuntimes",
            dependencies: ["ApplyPatch"],
            path: "tools/runtimes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
