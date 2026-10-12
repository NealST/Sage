// swift-tools-version: 6.0
//
// Execute harness modules. Source paths match the Sage tree so a Sage file
// and its Swift port stay side by side (EXECUTE_HARNESS_PORT_PLAN.md §5):
//
//   codex-rs/protocol/src/<file>.rs
//     → protocol/src/<file>.swift             module SageProtocol
//   codex-rs/file-system/src/lib.rs
//     → file-system/src/lib.swift             module FileSystem
//   codex-rs/apply-patch/src/<file>.rs
//     → apply-patch/src/<file>.swift          module ApplyPatch
//   codex-rs/git-utils/src/<file>.rs
//     → git-utils/src/<file>.swift            module SageGitUtils
//   codex-rs/core/src/tools/runtimes/<file>.rs
//     → tools/runtimes/<file>.swift           module ToolsRuntimes
//   codex-rs/sandboxing/src/<file>.rs
//     → sandboxing/src/<file>.swift           module SageSandboxing
//   codex-rs/shell-command/src/<file>.rs
//     → shell-command/src/<file>.swift        module SageShellCommand
//   codex-rs/execpolicy/src/<file>.rs
//     → execpolicy/src/<file>.swift           module SageExecPolicy
//   codex-rs/context-fragments/src/<file>.rs
//     → context-fragments/src/<file>.swift    module SageContextFragments
//   codex-rs/agent-roles/src/<file>.rs
//     → agent-roles/src/<file>.swift          module SageAgentRoles
//   codex-rs/hooks/src/<file>.rs
//     → hooks/src/<file>.swift                module SageHooks
//   codex-rs/skills/src/<file>.rs
//     → skills/src/<file>.swift               module SageSkills
//   codex-rs/otel/src/<file>.rs
//     → otel/src/<file>.swift                 module SageOtel
//   codex-rs/terminal-detection/src/<file>.rs
//     → terminal-detection/src/<file>.swift   module SageTerminalDetection
//
// `tools/handlers`, `tools/*.swift`, `session`, and `tasks` stay in the Sage
// app module. They close over Sage session types (PathGuard, AgentTool,
// TurnCoordinator). Sage keeps those in one core crate too; Swift splits a
// module only where a second file must reuse a Sage name (`apply_patch`).
//
// Per-file port state is tracked in PORTING.md (scripts/harness_port.py).

import PackageDescription

let package = Package(
    name: "ExecuteHarness",
    // .v15: SageProtocol uses UInt128 (ThreadId.init(u128:)), available macOS 15+.
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SageProtocol", targets: ["SageProtocol"]),
        .library(name: "SageUtils", targets: ["SageUtils"]),
        .library(name: "SageAsyncUtils", targets: ["SageAsyncUtils"]),
        .library(name: "FileSystem", targets: ["FileSystem"]),
        .library(name: "ApplyPatch", targets: ["ApplyPatch"]),
        .library(name: "SageGitUtils", targets: ["SageGitUtils"]),
        .library(name: "SageSandboxing", targets: ["SageSandboxing"]),
        .library(name: "SageShellCommand", targets: ["SageShellCommand"]),
        .library(name: "SageExecPolicy", targets: ["SageExecPolicy"]),
        .library(name: "SageCore", targets: ["SageCore"]),
        .library(name: "SageNetworkProxy", targets: ["SageNetworkProxy"]),
        .library(name: "SageModelProviderInfo", targets: ["SageModelProviderInfo"]),
        .library(name: "SageAPI", targets: ["SageAPI"]),
        .library(name: "SageHistory", targets: ["SageHistory"]),
        .library(name: "SageRollout", targets: ["SageRollout"]),
        .library(name: "SageState", targets: ["SageState"]),
        .library(name: "SageThreadStore", targets: ["SageThreadStore"]),
        .library(name: "SageContextFragments", targets: ["SageContextFragments"]),
        .library(name: "SageAgentRoles", targets: ["SageAgentRoles"]),
        .library(name: "SageHooks", targets: ["SageHooks"]),
        .library(name: "SageSkills", targets: ["SageSkills"]),
        .library(name: "SageTerminalDetection", targets: ["SageTerminalDetection"]),
        .library(name: "ToolsRuntimes", targets: ["ToolsRuntimes"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: "0.23.0"),
    ],
    targets: [
        // codex-rs/protocol depends on the codex-utils crates (path-uri,
        // absolute-path, image, ...), so SageProtocol depends on SageUtils.
        // In the Sage app target these sources are also compiled directly
        // (synchronized folder), where same-module shadowing keeps references
        // resolving to the app-module copies.
        .target(
            name: "SageProtocol",
            dependencies: ["SageUtils"],
            path: "protocol/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // All codex-rs/utils/* crates compile into one module (plan §4.1).
        .target(
            name: "SageUtils",
            path: "utils",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/async-utils — separate module because an SPM target has a
        // single path and async-utils/ is not under utils/ (plan §4.1 note).
        .target(
            name: "SageAsyncUtils",
            path: "async-utils/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "FileSystem",
            dependencies: ["SageProtocol", "SageUtils"],
            path: "file-system/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ApplyPatch",
            dependencies: ["FileSystem", "SageUtils"],
            path: "apply-patch/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/git-utils — Phase 2 (info/baseline/apply/trust first).
        // trust.rs uses ExecutorFileSystem, so this target also depends on FileSystem
        // (same as upstream `codex-file-system`).
        .target(
            name: "SageGitUtils",
            dependencies: ["SageProtocol", "SageUtils", "FileSystem"],
            path: "git-utils/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ToolsRuntimes",
            dependencies: ["ApplyPatch", "SageProtocol"],
            path: "tools/runtimes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // network-proxy type layer only (plan §2.3 / Phase 4). The local
        // proxy process stays excluded.
        .target(
            name: "SageNetworkProxy",
            path: "network-proxy/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/model-provider-info — Phase 6 provider catalog.
        .target(
            name: "SageModelProviderInfo",
            dependencies: ["SageProtocol"],
            path: "model-provider-info/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/codex-api — Phase 6 SSE / Responses subset.
        // Realtime/websocket files stay deferred (Phase 10).
        .target(
            name: "SageAPI",
            dependencies: ["SageProtocol", "SageUtils", "SageModelProviderInfo"],
            path: "sage-api/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/history — rollout JSONL item wire types. Not listed as its
        // own crate in PORTING.md; rollout depends on it.
        .target(
            name: "SageHistory",
            dependencies: ["SageProtocol"],
            path: "history/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/rollout — JSONL recorder / list / compression (Phase 7).
        .target(
            name: "SageRollout",
            dependencies: ["SageProtocol", "SageHistory", "SageState", "SageUtils"],
            path: "rollout/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Slim types for rollout / in-memory child sessions. Sage
        // memories/goals/remote_control runtime was removed.
        .target(
            name: "SageState",
            dependencies: ["SageProtocol", "SageHistory"],
            path: "state/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // In-memory thread store for child-agent sessions. Sage thread
        // product (local JSONL listing/archive) was removed.
        .target(
            name: "SageThreadStore",
            dependencies: ["SageProtocol", "SageHistory", "SageRollout", "SageState"],
            path: "thread-store/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/sandboxing — Phase 3. macOS seatbelt path is faithful;
        // landlock/bwrap/windows are excluded(platform). Network-proxy types
        // used by seatbelt/violation are inlined (plan §2.3 / Phase 4).
        .target(
            name: "SageSandboxing",
            dependencies: ["SageProtocol", "SageUtils"],
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
            name: "SageShellCommand",
            dependencies: [
                "SageProtocol",
                "SageUtils",
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
            name: "SageExecPolicy",
            dependencies: ["SageUtils"],
            path: "execpolicy/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/context-fragments — Phase 8 faithful fragment types.
        .target(
            name: "SageContextFragments",
            dependencies: ["SageProtocol", "SageUtils"],
            path: "context-fragments/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/agent-roles — types + discovery faithful; loader adapted
        // without ConfigLayerStack (plan §Phase 8).
        .target(
            name: "SageAgentRoles",
            dependencies: ["SageUtils", "FileSystem"],
            path: "agent-roles/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/hooks — types/events/engine; schema fixtures are bundled.
        .target(
            name: "SageHooks",
            dependencies: ["SageProtocol", "SageUtils"],
            path: "hooks/src",
            resources: [
                .copy("schema/generated"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // codex-rs/skills — Phase 8 model/parser/mentions/selection.
        // install_system_skills throws until sample assets are SPM resources.
        .target(
            name: "SageSkills",
            dependencies: ["SageProtocol", "SageUtils", "SageShellCommand"],
            path: "skills/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Terminal detection — environment-only probe.
        .target(
            name: "SageTerminalDetection",
            path: "terminal-detection/src",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Phase 3 core files. They sit at the Harness root so paths stay 1:1
        // with codex-rs/core/src, but Xcode will not compile a nested Swift
        // package into the app target. SageCore is the compile home until
        // the rest of core moves here in Phase 4–5.
        .target(
            name: "SageCore",
            dependencies: [
                "SageProtocol",
                "SageUtils",
                "SageAsyncUtils",
                "FileSystem",
                "ApplyPatch",
                "SageSandboxing",
                "SageShellCommand",
                "SageExecPolicy",
                "SageNetworkProxy",
                "SageModelProviderInfo",
                "SageAPI",
                "SageHistory",
                "SageRollout",
                "SageState",
                "SageThreadStore",
                "SageContextFragments",
                "SageAgentRoles",
                "SageHooks",
                "SageSkills",
                "SageTerminalDetection",
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
                "session_prefix.swift",
                "session_startup_prewarm.swift",
                "rollout_budget.swift",
                "thread_startup_metadata.swift",
                "memory_usage.swift",
                "session_rollout_init_error.swift",
                "thread_rollout_truncation.swift",
                "rollout.swift",
                "state_db_bridge.swift",
                "thread_manager.swift",
                "thread_manager",
                "sage_thread.swift",
                "sage_delegate.swift",
                "session/session_mod.swift",
                "session/turn_input.swift",
                "mention_syntax.swift",
                "elicitation.swift",
                "hook_mcp_executor.swift",
                "skills.swift",
                "core_agents_md.swift",
                "agents_md_manager.swift",
                "agent",
                "agent_communication.swift",
                "agent_message_board.swift",
                "session_multi_agents.swift",
                "core_test_support.swift",
                "lib.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "Phase7PersistenceTests",
            dependencies: [
                "SageHistory",
                "SageProtocol",
                "SageRollout",
                "SageState",
                "SageThreadStore",
            ],
            path: "Tests/Phase7PersistenceTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "Phase8GuardianSkillsTests",
            dependencies: [
                "SageAgentRoles",
                "SageContextFragments",
                "SageCore",
                "SageHooks",
                "SageProtocol",
                "SageSkills",
                "SageUtils",
                "FileSystem",
            ],
            path: "Tests/Phase8GuardianSkillsTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "Phase9AgentTests",
            dependencies: [
                "SageAgentRoles",
                "SageAPI",
                "SageAsyncUtils",
                "SageCore",
                "SageHistory",
                "SageProtocol",
                "SageSkills",
                "SageUtils",
            ],
            path: "Tests/Phase9AgentTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
