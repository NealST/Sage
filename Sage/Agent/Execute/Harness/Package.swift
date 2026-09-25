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
//   codex-rs/git-utils/src/<file>.rs
//     → git-utils/src/<file>.swift            module CodexGitUtils
//   codex-rs/core/src/tools/runtimes/<file>.rs
//     → tools/runtimes/<file>.swift           module ToolsRuntimes
//   codex-rs/sandboxing/src/<file>.rs
//     → sandboxing/src/<file>.swift           module CodexSandboxing
//   codex-rs/shell-command/src/<file>.rs
//     → shell-command/src/<file>.swift        module CodexShellCommand
//   codex-rs/execpolicy/src/<file>.rs
//     → execpolicy/src/<file>.swift           module CodexExecPolicy
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
        .library(name: "CodexGitUtils", targets: ["CodexGitUtils"]),
        .library(name: "CodexSandboxing", targets: ["CodexSandboxing"]),
        .library(name: "CodexShellCommand", targets: ["CodexShellCommand"]),
        .library(name: "CodexExecPolicy", targets: ["CodexExecPolicy"]),
        .library(name: "ToolsRuntimes", targets: ["ToolsRuntimes"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: "0.23.0"),
    ],
    targets: [
        // codex-rs/protocol depends on the codex-utils crates (path-uri,
        // absolute-path, image, ...), so CodexProtocol depends on CodexUtils.
        // In the Sage app target these sources are also compiled directly
        // (synchronized folder), where same-module shadowing keeps references
        // resolving to the app-module copies.
        .target(
            name: "CodexProtocol",
            dependencies: ["CodexUtils"],
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
            dependencies: ["CodexProtocol", "CodexUtils"],
            path: "file-system/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ApplyPatch",
            dependencies: ["FileSystem", "CodexUtils"],
            path: "apply-patch/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/git-utils — Phase 2 (info/baseline/apply/trust first).
        // trust.rs uses ExecutorFileSystem, so this target also depends on FileSystem
        // (same as upstream `codex-file-system`).
        .target(
            name: "CodexGitUtils",
            dependencies: ["CodexProtocol", "CodexUtils", "FileSystem"],
            path: "git-utils/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ToolsRuntimes",
            dependencies: ["ApplyPatch"],
            path: "tools/runtimes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/sandboxing — Phase 3. macOS seatbelt path is faithful;
        // landlock/bwrap/windows are excluded(platform). Network-proxy types
        // used by seatbelt/violation are inlined (plan §2.3 / Phase 4).
        .target(
            name: "CodexSandboxing",
            dependencies: ["CodexProtocol", "CodexUtils"],
            path: "sandboxing/src",
            resources: [
                .copy("seatbelt_base_policy.sbpl"),
                .copy("seatbelt_network_policy.sbpl"),
                .copy("seatbelt_preferences_policy.sbpl"),
                .copy("seatbelt_read_only_platform_defaults.sbpl"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/shell-command — Phase 3. bash/zsh/sh + parse_command are
        // faithful; PowerShell/Windows files are adapted stubs.
        .target(
            name: "CodexShellCommand",
            dependencies: [
                "CodexProtocol",
                "CodexUtils",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
            ],
            path: "shell-command/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/execpolicy — Phase 3. Decision/rule/policy matching is
        // faithful; PolicyParser is a prefix-rule subset evaluator (plan §10.1)
        // because Swift has no Starlark crate.
        .target(
            name: "CodexExecPolicy",
            dependencies: ["CodexUtils"],
            path: "execpolicy/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
