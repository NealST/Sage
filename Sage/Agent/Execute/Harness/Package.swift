// swift-tools-version: 6.0
//
// Execute harness modules. Source paths match the Codex tree so a Codex file
// and its Swift port stay side by side:
//
//   codex-rs/apply-patch/src/<file>.rs
//     → apply-patch/src/<file>.swift          module ApplyPatch
//   codex-rs/core/src/tools/runtimes/<file>.rs
//     → tools/runtimes/<file>.swift           module ToolsRuntimes
//
// `tools/handlers`, `tools/*.swift`, `session`, and `tasks` stay in the Sage
// app module. They close over Sage session types (PathGuard, AgentTool,
// TurnCoordinator). Codex keeps those in one core crate too; Swift splits a
// module only where a second file must reuse a Codex name (`apply_patch`).

import PackageDescription

let package = Package(
    name: "ExecuteHarness",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ApplyPatch", targets: ["ApplyPatch"]),
        .library(name: "ToolsRuntimes", targets: ["ToolsRuntimes"]),
    ],
    targets: [
        .target(
            name: "ApplyPatch",
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
