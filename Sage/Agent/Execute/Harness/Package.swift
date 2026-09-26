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
//   codex-rs/context-fragments/src/<file>.rs
//     → context-fragments/src/<file>.swift    module CodexContextFragments
//   codex-rs/agent-roles/src/<file>.rs
//     → agent-roles/src/<file>.swift          module CodexAgentRoles
//   codex-rs/hooks/src/<file>.rs
//     → hooks/src/<file>.swift                module CodexHooks
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
        .library(name: "CodexCore", targets: ["CodexCore"]),
        .library(name: "CodexNetworkProxy", targets: ["CodexNetworkProxy"]),
        .library(name: "CodexModelProviderInfo", targets: ["CodexModelProviderInfo"]),
        .library(name: "CodexAPI", targets: ["CodexAPI"]),
        .library(name: "CodexHistory", targets: ["CodexHistory"]),
        .library(name: "CodexRollout", targets: ["CodexRollout"]),
        .library(name: "CodexState", targets: ["CodexState"]),
        .library(name: "CodexThreadStore", targets: ["CodexThreadStore"]),
        .library(name: "CodexContextFragments", targets: ["CodexContextFragments"]),
        .library(name: "CodexAgentRoles", targets: ["CodexAgentRoles"]),
        .library(name: "CodexHooks", targets: ["CodexHooks"]),
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
            dependencies: ["ApplyPatch", "CodexProtocol"],
            path: "tools/runtimes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // network-proxy type layer only (plan §2.3 / Phase 4). The local
        // proxy process stays excluded.
        .target(
            name: "CodexNetworkProxy",
            path: "network-proxy/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/model-provider-info — Phase 6 provider catalog.
        .target(
            name: "CodexModelProviderInfo",
            dependencies: ["CodexProtocol"],
            path: "model-provider-info/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/codex-api — Phase 6 SSE / Responses subset.
        // Realtime/websocket files stay deferred (Phase 10).
        .target(
            name: "CodexAPI",
            dependencies: ["CodexProtocol", "CodexUtils", "CodexModelProviderInfo"],
            path: "codex-api/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/history — rollout JSONL item wire types. Not listed as its
        // own crate in PORTING.md; rollout depends on it.
        .target(
            name: "CodexHistory",
            dependencies: ["CodexProtocol"],
            path: "history/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/rollout — JSONL recorder / list / compression (Phase 7).
        .target(
            name: "CodexRollout",
            dependencies: ["CodexProtocol", "CodexHistory", "CodexState", "CodexUtils"],
            path: "rollout/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/state — models + GRDB adapter. Path is state/src so it
        // does not collide with Harness/state/ (Phase 5 session services).
        .target(
            name: "CodexState",
            dependencies: ["CodexProtocol", "CodexHistory"],
            path: "state/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/thread-store — types + in-memory / local GRDB store.
        .target(
            name: "CodexThreadStore",
            dependencies: ["CodexProtocol", "CodexHistory", "CodexRollout", "CodexState"],
            path: "thread-store/src",
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
        // codex-rs/context-fragments — Phase 8 faithful fragment types.
        .target(
            name: "CodexContextFragments",
            dependencies: ["CodexProtocol", "CodexUtils"],
            path: "context-fragments/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/agent-roles — types + discovery faithful; loader adapted
        // without ConfigLayerStack (plan §Phase 8).
        .target(
            name: "CodexAgentRoles",
            dependencies: ["CodexUtils", "FileSystem"],
            path: "agent-roles/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/hooks — mcp/types/lib first; engine/events stay unstarted.
        .target(
            name: "CodexHooks",
            dependencies: ["CodexProtocol", "CodexUtils"],
            path: "hooks/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Phase 3 core files. They sit at the Harness root so paths stay 1:1
        // with codex-rs/core/src, but Xcode will not compile a nested Swift
        // package into the app target. CodexCore is the compile home until
        // the rest of core moves here in Phase 4–5.
        .target(
            name: "CodexCore",
            dependencies: [
                "CodexProtocol",
                "CodexUtils",
                "CodexAsyncUtils",
                "FileSystem",
                "ApplyPatch",
                "CodexSandboxing",
                "CodexShellCommand",
                "CodexExecPolicy",
                "CodexNetworkProxy",
                "CodexModelProviderInfo",
                "CodexAPI",
                "CodexHistory",
                "CodexRollout",
                "CodexState",
                "CodexThreadStore",
                "CodexContextFragments",
                "CodexHooks",
            ],
            path: ".",
            sources: [
                "exec.swift",
                "exec_env.swift",
                "exec_policy.swift",
                "exec_policy",
                "apply_patch.swift",
                "function_tool.swift",
                "network_policy_decision.swift",
                "spawn.swift",
                "shell.swift",
                "shell_snapshot.swift",
                "shell_snapshot_sandbox.swift",
                "safety.swift",
                "sandbox_tags.swift",
                "user_shell_command.swift",
                "command_canonicalization.swift",
                "sandboxing_mod.swift",
                "unified_exec",
                "context",
                "context_manager",
                "compact.swift",
                "compact_model_fallback.swift",
                "compact_remote_history.swift",
                "compact_remote_v2.swift",
                "compact_remote_v2_attempt.swift",
                "compact_remote_v2_images.swift",
                "compact_token_budget.swift",
                "event_mapping.swift",
                "stream_events_utils.swift",
                "turn_diff_tracker.swift",
                "turn_metadata.swift",
                "turn_timing.swift",
                "mcp.swift",
                "mcp_openai_file.swift",
                "mcp_skill_dependencies.swift",
                "mcp_tool_approval_templates.swift",
                "mcp_tool_call.swift",
                "mcp_tool_call",
                "mcp_tool_exposure.swift",
                "client.swift",
                "client_common.swift",
                "client_tool_metadata.swift",
                "current_time.swift",
                "image_preparation.swift",
                "model_request.swift",
                "original_image_detail.swift",
                "prompt_debug.swift",
                "responses_headers.swift",
                "responses_metadata.swift",
                "responses_retry.swift",
                "web_search.swift",
                "attestation.swift",
                "installation_id.swift",
                "session_prefix.swift",
                "rollout_budget.swift",
                "thread_startup_metadata.swift",
                "memory_usage.swift",
                "feedback_config.swift",
                "session_rollout_init_error.swift",
                "thread_rollout_truncation.swift",
                "rollout.swift",
                "state_db_bridge.swift",
                "thread_manager.swift",
                "thread_manager",
                "codex_thread.swift",
                "codex_delegate.swift",
                "mention_syntax.swift",
                "elicitation.swift",
                "hook_mcp_executor.swift",
                "skills.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "Phase7PersistenceTests",
            dependencies: [
                "CodexHistory",
                "CodexProtocol",
                "CodexRollout",
                "CodexState",
                "CodexThreadStore",
            ],
            path: "Tests/Phase7PersistenceTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "Phase8GuardianSkillsTests",
            dependencies: [
                "CodexAgentRoles",
                "CodexContextFragments",
                "CodexCore",
                "CodexHooks",
                "CodexProtocol",
                "CodexUtils",
                "FileSystem",
            ],
            path: "Tests/Phase8GuardianSkillsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
