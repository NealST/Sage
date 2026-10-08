# Execute Harness 移植追踪表

> 由 `scripts/harness_port.py generate` 生成（0a2eb469 基线）。
> 状态随 PR 手工更新；`check` 模式校验文件头与本表一致。
> 重新生成会保留未移植行的手工状态与备注；已移植行以 Swift 文件头为准。

状态图例：✅ faithful ｜ 🟡 adapted / partial ｜ 🟥 stub ｜ ⬜ 未开始 ｜ ⛔ excluded(platform/test) ｜ 💤 deferred

## 进度汇总

| Phase | 文件数 | ✅ | 🟡 | 🟥 | ⬜ | ⛔/💤 |
|---|---:|---:|---:|---:|---:|---:|
| Phase 1 | 94 | 69 | 25 | 0 | 0 | 0 |
| Phase 2 | 26 | 10 | 15 | 0 | 0 | 0 |
| Phase 3 | 82 | 19 | 52 | 0 | 0 | 0 |
| Phase 4 | 112 | 11 | 60 | 0 | 0 | 0 |
| Phase 5 | 155 | 27 | 128 | 0 | 0 | 0 |
| Phase 6 | 49 | 4 | 32 | 0 | 0 | 0 |
| Phase 7 | 126 | 6 | 120 | 0 | 0 | 0 |
| Phase 8 | 70 | 22 | 47 | 0 | 0 | 0 |
| Phase 9 | 73 | 10 | 59 | 0 | 0 | 0 |
| Phase 10 | 38 | 7 | 18 | 0 | 0 | 0 |

## Phase 1

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/util.rs` | 101 | `util.swift` | 🟡 adapted |  |
| `core/src/utils/json.rs` | 22 | `utils/json.swift` | 🟡 adapted |  |
| `core/src/utils/mod.rs` | 2 | `utils/mod.swift` | ✅ faithful |  |
| `core/src/utils/path_utils.rs` | 1 | `utils/path_utils.swift` | ✅ faithful |  |
| `async-utils/src/backoff.rs` | 17 | `async-utils/src/backoff.swift` | ✅ faithful |  |
| `async-utils/src/lib.rs` | 93 | `async-utils/src/lib.swift` | 🟡 adapted |  |
| `protocol/src/account.rs` | 259 | `protocol/src/account.swift` | ✅ faithful |  |
| `protocol/src/agent_path.rs` | 240 | `protocol/src/agent_path.swift` | ✅ faithful |  |
| `protocol/src/approvals.rs` | 548 | `protocol/src/approvals.swift` | ✅ faithful |  |
| `protocol/src/auth.rs` | 249 | `protocol/src/auth.swift` | ✅ faithful |  |
| `protocol/src/capabilities.rs` | 51 | `protocol/src/capabilities.swift` | ✅ faithful |  |
| `protocol/src/codex_error_info.rs` | 83 | `protocol/src/codex_error_info.swift` | ✅ faithful |  |
| `protocol/src/config_types.rs` | 980 | `protocol/src/config_types.swift` | ✅ faithful |  |
| `protocol/src/dynamic_tools.rs` | 175 | `protocol/src/dynamic_tools.swift` | ✅ faithful |  |
| `protocol/src/environment.rs` | 101 | `protocol/src/environment.swift` | 🟡 adapted |  |
| `protocol/src/error.rs` | 890 | `protocol/src/error.swift` | 🟡 adapted |  |
| `protocol/src/exec_output.rs` | 169 | `protocol/src/exec_output.swift` | 🟡 adapted |  |
| `protocol/src/items.rs` | 869 | `protocol/src/items.swift` | 🟡 adapted |  |
| `protocol/src/legacy_events.rs` | 685 | `protocol/src/legacy_events.swift` | ✅ faithful |  |
| `protocol/src/lib.rs` | 56 | `protocol/src/lib.swift` | ✅ faithful |  |
| `protocol/src/local_media.rs` | 96 | `protocol/src/local_media.swift` | ✅ faithful |  |
| `protocol/src/mcp.rs` | 587 | `protocol/src/mcp.swift` | ✅ faithful |  |
| `protocol/src/mcp_approval_meta.rs` | 29 | `protocol/src/mcp_approval_meta.swift` | ✅ faithful |  |
| `protocol/src/mcp_policy.rs` | 96 | `protocol/src/mcp_policy.swift` | ✅ faithful |  |
| `protocol/src/memory_citation.rs` | 20 | `protocol/src/memory_citation.swift` | ✅ faithful |  |
| `protocol/src/memory_version.rs` | 23 | `protocol/src/memory_version.swift` | ✅ faithful |  |
| `protocol/src/models/configuration_update.rs` | 17 | `protocol/src/models/configuration_update.swift` | ✅ faithful |  |
| `protocol/src/models/executed_tool_calls.rs` | 612 | `protocol/src/models/executed_tool_calls.swift` | ✅ faithful |  |
| `protocol/src/models/item_metadata.rs` | 11 | `protocol/src/models/item_metadata.swift` | ✅ faithful |  |
| `protocol/src/models.rs` | 4,565 | `protocol/src/models.swift` | 🟡 adapted |  |
| `protocol/src/network_policy.rs` | 22 | `protocol/src/network_policy.swift` | 🟡 adapted |  |
| `protocol/src/num_format.rs` | 29 | `protocol/src/num_format.swift` | ✅ faithful |  |
| `protocol/src/openai_models/access_programs.rs` | 31 | `protocol/src/openai_models/access_programs.swift` | ✅ faithful |  |
| `protocol/src/openai_models/guardian.rs` | 179 | `protocol/src/openai_models/guardian.swift` | ✅ faithful |  |
| `protocol/src/openai_models/guardian_v2.rs` | 48 | `protocol/src/openai_models/guardian_v2.swift` | ✅ faithful |  |
| `protocol/src/openai_models/reasoning_effort.rs` | 44 | `protocol/src/openai_models/reasoning_effort.swift` | ✅ faithful |  |
| `protocol/src/openai_models.rs` | 1,935 | `protocol/src/openai_models.swift` | ✅ faithful |  |
| `protocol/src/parse_command.rs` | 31 | `protocol/src/parse_command.swift` | ✅ faithful |  |
| `protocol/src/permission_profile_intersection.rs` | 425 | `protocol/src/permission_profile_intersection.swift` | ✅ faithful |  |
| `protocol/src/permission_profile_snapshot.rs` | 128 | `protocol/src/permission_profile_snapshot.swift` | ✅ faithful |  |
| `protocol/src/permissions/deny_read_validator.rs` | 102 | `protocol/src/permissions/deny_read_validator.swift` | ✅ faithful |  |
| `protocol/src/permissions/target.rs` | 195 | `protocol/src/permissions/target.swift` | ✅ faithful |  |
| `protocol/src/permissions/windows_glob.rs` | 44 | `protocol/src/permissions/windows_glob.swift` | ✅ faithful |  |
| `protocol/src/permissions.rs` | 4,488 | `protocol/src/permissions.swift` | 🟡 adapted |  |
| `protocol/src/plan_tool.rs` | 29 | `protocol/src/plan_tool.swift` | ✅ faithful |  |
| `protocol/src/protocol.rs` | 6,444 | `protocol/src/protocol.swift` | 🟡 adapted |  |
| `protocol/src/realtime.rs` | 59 | `protocol/src/realtime.swift` | ✅ faithful |  |
| `protocol/src/request_permissions.rs` | 99 | `protocol/src/request_permissions.swift` | ✅ faithful |  |
| `protocol/src/request_user_input.rs` | 103 | `protocol/src/request_user_input.swift` | ✅ faithful |  |
| `protocol/src/response_item_id.rs` | 70 | `protocol/src/response_item_id.swift` | ✅ faithful |  |
| `protocol/src/response_usage.rs` | 14 | `protocol/src/response_usage.swift` | ✅ faithful |  |
| `protocol/src/review_format.rs` | 82 | `protocol/src/review_format.swift` | ✅ faithful |  |
| `protocol/src/sandbox.rs` | 42 | `protocol/src/sandbox.swift` | ✅ faithful |  |
| `protocol/src/sanitized_git_url.rs` | 159 | `protocol/src/sanitized_git_url.swift` | 🟡 adapted |  |
| `protocol/src/security_risk.rs` | 25 | `protocol/src/security_risk.swift` | ✅ faithful |  |
| `protocol/src/session_id.rs` | 126 | `protocol/src/session_id.swift` | ✅ faithful |  |
| `protocol/src/shell_environment.rs` | 322 | `protocol/src/shell_environment.swift` | 🟡 adapted |  |
| `protocol/src/thread_id.rs` | 121 | `protocol/src/thread_id.swift` | ✅ faithful |  |
| `protocol/src/tool_name.rs` | 94 | `protocol/src/tool_name.swift` | ✅ faithful |  |
| `protocol/src/turn_input.rs` | 252 | `protocol/src/turn_input.swift` | ✅ faithful |  |
| `protocol/src/user_input.rs` | 126 | `protocol/src/user_input.swift` | ✅ faithful |  |
| `utils/absolute-path/src/absolutize.rs` | 171 | `utils/absolute-path/src/absolutize.swift` | ✅ faithful |  |
| `utils/absolute-path/src/lib.rs` | 780 | `utils/absolute-path/src/lib.swift` | ✅ faithful |  |
| `utils/audio/src/lib.rs` | 265 | `utils/audio/src/audio_lib.swift` | 🟡 adapted |  |
| `utils/cache/src/lib.rs` | 193 | `utils/cache/src/cache_lib.swift` | 🟡 adapted |  |
| `utils/git-discovery/src/lib.rs` | 120 | `utils/git-discovery/src/git_discovery_lib.swift` | 🟡 adapted |  |
| `utils/home-dir/src/lib.rs` | 134 | `utils/home-dir/src/home_dir_lib.swift` | ✅ faithful |  |
| `utils/image/src/error.rs` | 63 | `utils/image/src/error.swift` | 🟡 adapted |  |
| `utils/image/src/lib.rs` | 462 | `utils/image/src/image_lib.swift` | 🟡 adapted |  |
| `utils/output-truncation/src/lib.rs` | 215 | `utils/output-truncation/src/output_truncation_lib.swift` | 🟡 adapted |  |
| `utils/path-uri/src/absolute_path_normalization.rs` | 46 | `utils/path-uri/src/absolute_path_normalization.swift` | ✅ faithful |  |
| `utils/path-uri/src/api_path_string.rs` | 437 | `utils/path-uri/src/api_path_string.swift` | ✅ faithful |  |
| `utils/path-uri/src/config_path.rs` | 177 | `utils/path-uri/src/config_path.swift` | ✅ faithful |  |
| `utils/path-uri/src/lib.rs` | 1,042 | `utils/path-uri/src/path_uri_lib.swift` | 🟡 adapted |  |
| `utils/path-uri/src/native_path_bytes.rs` | 51 | `utils/path-uri/src/native_path_bytes.swift` | ✅ faithful |  |
| `utils/path-uri/src/platform.rs` | 51 | `utils/path-uri/src/platform.swift` | ✅ faithful |  |
| `utils/path-utils/src/env.rs` | 19 | `utils/path-utils/src/env.swift` | ✅ faithful |  |
| `utils/path-utils/src/lib.rs` | 242 | `utils/path-utils/src/path_utils_lib.swift` | 🟡 adapted |  |
| `utils/path-utils/src/system_commands.rs` | 166 | `utils/path-utils/src/system_commands.swift` | 🟡 adapted |  |
| `utils/plugins/src/lib.rs` | 53 | `utils/plugins/src/plugins_lib.swift` | 🟡 adapted |  |
| `utils/plugins/src/mcp_connector.rs` | 20 | `utils/plugins/src/mcp_connector.swift` | ✅ faithful |  |
| `utils/plugins/src/mention_syntax.rs` | 7 | `utils/plugins/src/mention_syntax.swift` | ✅ faithful |  |
| `utils/plugins/src/plugin_namespace.rs` | 366 | `utils/plugins/src/plugin_namespace.swift` | 🟡 adapted |  |
| `utils/stream-parser/src/assistant_text.rs` | 130 | `utils/stream-parser/src/assistant_text.swift` | ✅ faithful |  |
| `utils/stream-parser/src/citation.rs` | 179 | `utils/stream-parser/src/citation.swift` | ✅ faithful |  |
| `utils/stream-parser/src/inline_hidden_tag.rs` | 323 | `utils/stream-parser/src/inline_hidden_tag.swift` | ✅ faithful |  |
| `utils/stream-parser/src/lib.rs` | 23 | `utils/stream-parser/src/stream_parser_lib.swift` | ✅ faithful |  |
| `utils/stream-parser/src/proposed_plan.rs` | 212 | `utils/stream-parser/src/proposed_plan.swift` | ✅ faithful |  |
| `utils/stream-parser/src/stream_text.rs` | 36 | `utils/stream-parser/src/stream_text.swift` | ✅ faithful |  |
| `utils/stream-parser/src/tagged_line_parser.rs` | 249 | `utils/stream-parser/src/tagged_line_parser.swift` | ✅ faithful |  |
| `utils/stream-parser/src/utf8_stream.rs` | 333 | `utils/stream-parser/src/utf8_stream.swift` | ✅ faithful |  |
| `utils/string/src/json.rs` | 169 | `utils/string/src/string_json.swift` | 🟡 adapted |  |
| `utils/string/src/lib.rs` | 166 | `utils/string/src/string_lib.swift` | ✅ faithful |  |
| `utils/string/src/truncate.rs` | 156 | `utils/string/src/truncate.swift` | ✅ faithful |  |

## Phase 2

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `apply-patch/src/file_update.rs` | 335 | `apply-patch/src/file_update.swift` | ✅ faithful |  |
| `apply-patch/src/invocation.rs` | 1,036 | `apply-patch/src/invocation.swift` | ✅ faithful |  |
| `apply-patch/src/lib.rs` | 1,444 | `apply-patch/src/lib.swift` | ✅ faithful |  |
| `apply-patch/src/main.rs` | 3 | - | ⛔ excluded | 独立可执行入口，Sage 不需要 |
| `apply-patch/src/parser.rs` | 682 | `apply-patch/src/parser.swift` | ✅ faithful |  |
| `apply-patch/src/seek_sequence.rs` | 193 | `apply-patch/src/seek_sequence.swift` | ✅ faithful |  |
| `apply-patch/src/standalone_executable.rs` | 90 | `apply-patch/src/standalone_executable.swift` | 🟡 adapted | 适配项：Sage 进程内调用，无独立可执行 |
| `apply-patch/src/streaming_parser.rs` | 924 | `apply-patch/src/streaming_parser.swift` | ✅ faithful |  |
| `apply-patch/src/text_file.rs` | 121 | `apply-patch/src/text_file.swift` | ✅ faithful |  |
| `file-system/src/environment_accessor.rs` | 280 | `file-system/src/environment_accessor.swift` | 🟡 adapted |  |
| `file-system/src/exec_permission_profile_serde.rs` | 22 | `file-system/src/exec_permission_profile_serde.swift` | ✅ faithful |  |
| `file-system/src/find_up.rs` | 126 | `file-system/src/find_up.swift` | 🟡 adapted |  |
| `file-system/src/lib.rs` | 712 | `file-system/src/lib.swift` | 🟡 adapted |  |
| `git-utils/src/apply.rs` | 855 | `git-utils/src/apply.swift` | 🟡 adapted |  |
| `git-utils/src/baseline.rs` | 756 | `git-utils/src/baseline.swift` | 🟡 adapted |  |
| `git-utils/src/branch.rs` | 256 | `git-utils/src/branch.swift` | 🟡 adapted |  |
| `git-utils/src/errors.rs` | 35 | `git-utils/src/errors.swift` | 🟡 adapted |  |
| `git-utils/src/fsmonitor.rs` | 129 | `git-utils/src/fsmonitor.swift` | ✅ faithful |  |
| `git-utils/src/git_process.rs` | 106 | `git-utils/src/git_process.swift` | 🟡 adapted |  |
| `git-utils/src/info.rs` | 1,208 | `git-utils/src/info.swift` | 🟡 adapted |  |
| `git-utils/src/lib.rs` | 57 | `git-utils/src/lib.swift` | ✅ faithful |  |
| `git-utils/src/operations.rs` | 172 | `git-utils/src/operations.swift` | 🟡 adapted |  |
| `git-utils/src/platform.rs` | 37 | `git-utils/src/platform.swift` | 🟡 adapted |  |
| `git-utils/src/status.rs` | 83 | `git-utils/src/status.swift` | 🟡 adapted |  |
| `git-utils/src/trust.rs` | 183 | `git-utils/src/trust.swift` | 🟡 adapted |  |
| `git-utils/src/worktree.rs` | 178 | `git-utils/src/worktree.swift` | 🟡 adapted |  |

## Phase 3

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/apply_patch.rs` | 97 | `apply_patch.swift` | 🟡 adapted |  |
| `core/src/command_canonicalization.rs` | 42 | `command_canonicalization.swift` | ✅ faithful |  |
| `core/src/exec.rs` | 1,276 | `exec.swift` | 🟡 adapted |  |
| `core/src/exec_env.rs` | 117 | `exec_env.swift` | 🟡 adapted |  |
| `core/src/exec_policy/executable_identity.rs` | 107 | `exec_policy/executable_identity.swift` | 🟡 adapted |  |
| `core/src/exec_policy/model_policy.rs` | 60 | `exec_policy/model_policy.swift` | ✅ faithful |  |
| `core/src/exec_policy.rs` | 1,175 | `exec_policy.swift` | 🟡 adapted |  |
| `core/src/safety.rs` | 144 | `safety.swift` | ✅ faithful |  |
| `core/src/sandbox_tags.rs` | 114 | `sandbox_tags.swift` | 🟡 adapted |  |
| `core/src/sandboxing/mod.rs` | 218 | `sandboxing_mod.swift` | 🟡 adapted |  |
| `core/src/shell.rs` | 104 | `shell.swift` | 🟡 adapted |  |
| `core/src/shell_snapshot.rs` | 1,169 | `shell_snapshot.swift` | 🟡 adapted |  |
| `core/src/shell_snapshot_sandbox.rs` | 224 | `shell_snapshot_sandbox.swift` | 🟡 adapted |  |
| `core/src/spawn.rs` | 137 | `spawn.swift` | 🟡 adapted |  |
| `core/src/unified_exec/async_watcher.rs` | 482 | `unified_exec/async_watcher.swift` | 🟡 adapted |  |
| `core/src/unified_exec/errors.rs` | 71 | `unified_exec/errors.swift` | 🟡 adapted |  |
| `core/src/unified_exec/head_tail_buffer.rs` | 169 | `unified_exec/head_tail_buffer.swift` | ✅ faithful |  |
| `core/src/unified_exec/mod.rs` | 249 | `unified_exec/mod.swift` | 🟡 adapted |  |
| `core/src/unified_exec/oneshot.rs` | 123 | `unified_exec/oneshot.swift` | 🟡 adapted |  |
| `core/src/unified_exec/process.rs` | 652 | `unified_exec/process.swift` | 🟡 adapted |  |
| `core/src/unified_exec/process_manager.rs` | 1,881 | `unified_exec/process_manager.swift` | 🟡 adapted | spawn + stdin approval throw; HUD card stays out of runTurn |
| `core/src/unified_exec/process_state.rs` | 27 | `unified_exec/process_state.swift` | ✅ faithful |  |
| `core/src/unified_exec/shell_snapshot.rs` | 202 | `unified_exec/unified_exec_shell_snapshot.swift` | 🟡 adapted | request construction; session prewarm stays out |
| `core/src/unified_exec/stdin_approval.rs` | 249 | `unified_exec/stdin_approval.swift` | 🟡 adapted | StdinApprovalNeed + NUL/denied-read; TurnEnvironment stays out |
| `core/src/user_shell_command.rs` | 44 | `user_shell_command.swift` | 🟡 adapted | record + format + ResponseItem; TurnContext fragments stay out |
| `execpolicy/src/amend.rs` | 337 | `execpolicy/src/amend.swift` | 🟡 adapted |  |
| `execpolicy/src/decision.rs` | 27 | `execpolicy/src/decision.swift` | ✅ faithful |  |
| `execpolicy/src/error.rs` | 101 | `execpolicy/src/error.swift` | 🟡 adapted |  |
| `execpolicy/src/execpolicycheck.rs` | 95 | `execpolicy/src/execpolicycheck.swift` | 🟡 adapted |  |
| `execpolicy/src/executable_name.rs` | 29 | `execpolicy/src/executable_name.swift` | ✅ faithful |  |
| `execpolicy/src/lib.rs` | 33 | `execpolicy/src/lib.swift` | ✅ faithful |  |
| `execpolicy/src/main.rs` | 18 | - | ⛔ excluded | 独立 CLI 入口，Sage 不需要 |
| `execpolicy/src/parser.rs` | 473 | `execpolicy/src/parser.swift` | 🟡 adapted |  |
| `execpolicy/src/policy.rs` | 412 | `execpolicy/src/policy.swift` | ✅ faithful |  |
| `execpolicy/src/rule.rs` | 306 | `execpolicy/src/rule.swift` | ✅ faithful |  |
| `execpolicy/src/sandbox_migration.rs` | 123 | `execpolicy/src/sandbox_migration.swift` | 🟡 adapted |  |
| `sandboxing/src/bwrap.rs` | 195 | - | ⛔ excluded | platform: Linux |
| `sandboxing/src/denial.rs` | 72 | `sandboxing/src/denial.swift` | ✅ faithful |  |
| `sandboxing/src/landlock.rs` | 115 | - | ⛔ excluded | platform: Linux |
| `sandboxing/src/lib.rs` | 98 | `sandboxing/src/lib.swift` | 🟡 adapted |  |
| `sandboxing/src/manager.rs` | 802 | `sandboxing/src/manager.swift` | 🟡 adapted |  |
| `sandboxing/src/policy_transforms.rs` | 670 | `sandboxing/src/policy_transforms.swift` | 🟡 adapted |  |
| `sandboxing/src/seatbelt.rs` | 1,122 | `sandboxing/src/seatbelt.swift` | 🟡 adapted |  |
| `sandboxing/src/seatbelt_daemon.rs` | 24 | `sandboxing/src/seatbelt_daemon.swift` | ✅ faithful |  |
| `sandboxing/src/seatbelt_scratch.rs` | 69 | `sandboxing/src/seatbelt_scratch.swift` | ✅ faithful |  |
| `sandboxing/src/spawn.rs` | 141 | `sandboxing/src/spawn.swift` | 🟡 adapted |  |
| `sandboxing/src/terminal_queries.rs` | 104 | `sandboxing/src/terminal_queries.swift` | 🟡 adapted |  |
| `sandboxing/src/violation.rs` | 300 | `sandboxing/src/violation.swift` | 🟡 adapted |  |
| `sandboxing/src/windows.rs` | 401 | - | ⛔ excluded | platform: Windows |
| `sandboxing/src/windows_mxc.rs` | 22 | - | ⛔ excluded | platform: Windows |
| `shell-command/src/bash.rs` | 565 | `shell-command/src/bash.swift` | ✅ faithful |  |
| `shell-command/src/command_safety/is_dangerous_command.rs` | 323 | `shell-command/src/command_safety/is_dangerous_command.swift` | ✅ faithful |  |
| `shell-command/src/command_safety/mod.rs` | 9 | `shell-command/src/command_safety/mod.swift` | ✅ faithful |  |
| `shell-command/src/command_safety/powershell_parser.rs` | 373 | `shell-command/src/command_safety/powershell_parser.swift` | 🟡 adapted | 适配项：macOS 不需要 PowerShell 解析 |
| `shell-command/src/command_safety/powershell_tree_sitter.rs` | 482 | `shell-command/src/command_safety/powershell_tree_sitter.swift` | 🟡 adapted | 适配项：macOS 不需要 PowerShell 解析 |
| `shell-command/src/command_safety/windows_dangerous_commands.rs` | 771 | `shell-command/src/command_safety/windows_dangerous_commands.swift` | 🟡 adapted | 适配项：Windows 危险命令表 |
| `shell-command/src/lib.rs` | 14 | `shell-command/src/lib.swift` | ✅ faithful |  |
| `shell-command/src/parse_command.rs` | 2,766 | `shell-command/src/parse_command.swift` | 🟡 adapted |  |
| `shell-command/src/powershell.rs` | 291 | `shell-command/src/powershell.swift` | 🟡 adapted | 适配项：macOS 仅需 bash/zsh/sh，保留同名文件标注 |
| `shell-command/src/shell_detect.rs` | 495 | `shell-command/src/shell_detect.swift` | 🟡 adapted |  |
| `shell-command/src/shell_snapshot.rs` | 112 | `shell-command/src/shell_snapshot.swift` | 🟡 adapted |  |
| `shell-command/src/shell_snapshot_capture.rs` | 408 | `shell-command/src/shell_snapshot_capture.swift` | 🟡 adapted |  |
| `shell-command/src/shell_snapshot_credentials.rs` | 342 | `shell-command/src/shell_snapshot_credentials.swift` | 🟡 adapted |  |
| `shell-command/src/shell_snapshot_exports.rs` | 81 | `shell-command/src/shell_snapshot_exports.swift` | 🟡 adapted |  |
| `shell-command/src/shell_snapshot_literals.rs` | 715 | `shell-command/src/shell_snapshot_literals.swift` | 🟡 adapted |  |
| `shell-command/src/shell_snapshot_render.rs` | 106 | `shell-command/src/shell_snapshot_render.swift` | 🟡 adapted |  |
| `shell-command/src/startup.rs` | 30 | `shell-command/src/startup.swift` | ✅ faithful |  |
| `utils/pty/src/child.rs` | 96 | `utils/pty/src/child.swift` | 🟡 adapted |  |
| `utils/pty/src/child_command.rs` | 189 | `utils/pty/src/child_command.swift` | 🟡 adapted |  |
| `utils/pty/src/lib.rs` | 57 | `utils/pty/src/pty_lib.swift` | 🟡 adapted |  |
| `utils/pty/src/macos_child.rs` | 368 | `utils/pty/src/macos_child.swift` | 🟡 adapted |  |
| `utils/pty/src/pipe.rs` | 370 | `utils/pty/src/pipe.swift` | 🟡 adapted |  |
| `utils/pty/src/process.rs` | 481 | `utils/pty/src/process.swift` | 🟡 adapted |  |
| `utils/pty/src/process_group.rs` | 309 | `utils/pty/src/process_group.swift` | ✅ faithful |  |
| `utils/pty/src/pty.rs` | 563 | `utils/pty/src/pty.swift` | 🟡 adapted |  |
| `utils/pty/src/unix_io.rs` | 109 | `utils/pty/src/unix_io.swift` | 🟡 adapted |  |
| `utils/pty/src/win/conpty.rs` | 192 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/job.rs` | 232 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/mod.rs` | 181 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/procthreadattr.rs` | 127 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/psuedocon.rs` | 387 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/windows_input.rs` | 35 | - | ⛔ excluded | platform: Windows PTY |

## Phase 4

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/function_tool.rs` | 1 | `function_tool.swift` | 🟡 adapted |  |
| `core/src/network_policy_decision.rs` | 106 | `network_policy_decision.swift` | ✅ faithful |  |
| `core/src/tools/approvals.rs` | 884 | `tools/approvals.swift` | 🟡 adapted | HUD `from(step:)` classifies exec/stdin/patch/MCP/network/permissions; SessionToolAllowlist writes session keys into ApprovalStore |
| `core/src/tools/call_trace.rs` | 88 | `tools/call_trace.swift` | 🟡 adapted |  |
| `core/src/tools/catalog_parameters.rs` | 14 | `tools/catalog_parameters.swift` | ✅ faithful |  |
| `core/src/tools/context.rs` | 607 | `tools/context.swift` | 🟡 adapted |  |
| `core/src/tools/control_tool_analytics.rs` | 58 | `tools/control_tool_analytics.swift` | 🟡 adapted |  |
| `core/src/tools/events.rs` | 885 | `tools/events.swift` | 🟡 adapted |  |
| `core/src/tools/executed_tool_calls/mcp_attribution.rs` | 169 | `tools/executed_tool_calls/mcp_attribution.swift` | 🟡 adapted |  |
| `core/src/tools/executed_tool_calls/request_metadata.rs` | 441 | `tools/executed_tool_calls/request_metadata.swift` | 🟡 adapted |  |
| `core/src/tools/executed_tool_calls/seen_ids.rs` | 133 | `tools/executed_tool_calls/seen_ids.swift` | 🟡 adapted |  |
| `core/src/tools/executed_tool_calls.rs` | 629 | `tools/executed_tool_calls.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/apply_patch.rs` | 641 | `tools/handlers/apply_patch.swift` | 🟡 adapted | OnRequest/UnlessTrusted ask before dropping sandbox |
| `core/src/tools/handlers/apply_patch_spec.rs` | 32 | `tools/handlers/apply_patch_spec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/current_time.rs` | 130 | `tools/handlers/current_time.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/dynamic.rs` | 251 | `tools/handlers/dynamic.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/extension_tools.rs` | 640 | `tools/handlers/extension_tools.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/get_context_remaining.rs` | 94 | `tools/handlers/get_context_remaining.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/get_context_remaining_spec.rs` | 36 | `tools/handlers/get_context_remaining_spec.swift` | ✅ faithful |  |
| `core/src/tools/handlers/mcp.rs` | 882 | `tools/handlers/mcp.swift` | 🟡 adapted | per-tool handler; live invoke via Session.onMcpCall |
| `core/src/tools/handlers/mcp_resource/list_mcp_resource_templates.rs` | 102 | `tools/handlers/mcp_resource/list_mcp_resource_templates.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/mcp_resource/list_mcp_resources.rs` | 100 | `tools/handlers/mcp_resource/list_mcp_resources.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/mcp_resource/read_mcp_resource.rs` | 99 | `tools/handlers/mcp_resource/read_mcp_resource.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/mcp_resource.rs` | 414 | `tools/handlers/mcp_resource.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/mcp_resource_spec.rs` | 97 | `tools/handlers/mcp_resource_spec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/mod.rs` | 616 | `tools/handlers/handlers_mod.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/new_context_window.rs` | 48 | `tools/handlers/new_context_window.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/new_context_window_spec.rs` | 17 | `tools/handlers/new_context_window_spec.swift` | ✅ faithful |  |
| `core/src/tools/handlers/plan.rs` | 112 | `tools/handlers/plan.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/plan_spec.rs` | 58 | `tools/handlers/plan_spec.swift` | ✅ faithful |  |
| `core/src/tools/handlers/request_permissions.rs` | 209 | `tools/handlers/request_permissions.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/request_user_input.rs` | 175 | `tools/handlers/request_user_input.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/request_user_input_async.rs` | 144 | `tools/handlers/request_user_input_async.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/request_user_input_spec.rs` | 146 | `tools/handlers/request_user_input_spec.swift` | ✅ faithful |  |
| `core/src/tools/handlers/send_message_to_user_async.rs` | 109 | `tools/handlers/send_message_to_user_async.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/shell_spec.rs` | 348 | `tools/handlers/shell_spec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/sleep.rs` | 167 | `tools/handlers/sleep.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/test_sync.rs` | 196 | `tools/handlers/test_sync.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/test_sync_spec.rs` | 70 | `tools/handlers/test_sync_spec.swift` | ✅ faithful |  |
| `core/src/tools/handlers/tool_search.rs` | 487 | `tools/handlers/tool_search.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/tool_search_spec.rs` | 221 | `tools/handlers/tool_search_spec.swift` | ✅ faithful |  |
| `core/src/tools/handlers/unified_exec/exec_command.rs` | 569 | `tools/handlers/unified_exec/exec_command.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/unified_exec/write_stdin.rs` | 145 | `tools/handlers/unified_exec/write_stdin.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/unified_exec.rs` | 159 | `tools/handlers/unified_exec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/view_image.rs` | 526 | `tools/handlers/view_image.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/view_image_spec.rs` | 74 | `tools/handlers/view_image_spec.swift` | ✅ faithful |  |
| `core/src/tools/hook_names.rs` | 67 | `tools/hook_names.swift` | ✅ faithful |  |
| `core/src/tools/hosted_spec.rs` | 50 | `tools/hosted_spec.swift` | 🟡 adapted |  |
| `core/src/tools/lifecycle.rs` | 175 | `tools/lifecycle.swift` | 🟡 adapted |  |
| `core/src/tools/mod.rs` | 147 | `tools/tools_mod.swift` | 🟡 adapted | R4a basename |
| `core/src/tools/multi_agent_tool.rs` | 133 | `tools/multi_agent_tool.swift` | 🟡 adapted |  |
| `core/src/tools/network_approval.rs` | 1,254 | `tools/network_approval.swift` | 🟡 adapted |  |
| `core/src/tools/orchestrator.rs` | 551 | `tools/orchestrator.swift` | 🟡 adapted |  |
| `core/src/tools/parallel.rs` | 787 | `tools/parallel.swift` | 🟡 adapted |  |
| `core/src/tools/registry.rs` | 851 | `tools/registry.swift` | 🟡 adapted |  |
| `core/src/tools/router.rs` | 385 | `tools/router.swift` | 🟡 adapted |  |
| `core/src/tools/runtimes/apply_patch.rs` | 242 | `tools/runtimes/apply_patch.swift` | 🟡 partial |  |
| `core/src/tools/runtimes/mod.rs` | 918 | `tools/runtimes/mod.swift` | 🟡 adapted |  |
| `core/src/tools/runtimes/unified_exec.rs` | 975 | `tools/runtimes/unified_exec.swift` | 🟡 adapted |  |
| `core/src/tools/runtimes/zsh_fork/unix_escalation.rs` | 875 | `tools/runtimes/zsh_fork/unix_escalation.swift` | 🟡 adapted |  |
| `core/src/tools/runtimes/zsh_fork.rs` | 105 | `tools/runtimes/zsh_fork.swift` | 🟡 adapted |  |
| `core/src/tools/sandboxing.rs` | 561 | `tools/sandboxing.swift` | 🟡 adapted |  |
| `core/src/tools/spec_plan.rs` | 1,479 | `tools/spec_plan.swift` | 🟡 adapted |  |
| `core/src/tools/tool_dispatch_trace.rs` | 128 | `tools/tool_dispatch_trace.swift` | 🟡 adapted |  |
| `core/src/tools/tool_namespaces_info.rs` | 111 | `tools/tool_namespaces_info.swift` | 🟡 adapted |  |
| `core/src/tools/user_messaging.rs` | 33 | `tools/user_messaging.swift` | 🟡 adapted |  |
| `network-proxy/src/attribution.rs` | 145 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/authorization_path.rs` | 64 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/brokered_tunnel.rs` | 217 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/certs.rs` | 1,283 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/config.rs` | 1,233 | `network-proxy/src/config.swift` | 🟡 adapted | 策略类型层 |
| `network-proxy/src/connect_policy.rs` | 244 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/connection_lifecycle/listeners.rs` | 47 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/connection_lifecycle/mod.rs` | 12 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/connection_lifecycle/scope.rs` | 35 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/connection_lifecycle/service.rs` | 43 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/configured.rs` | 578 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/destination.rs` | 162 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/environment.rs` | 470 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/matching.rs` | 541 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/provider_config.rs` | 40 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/providers/github.rs` | 171 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/providers/openai.rs` | 95 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/providers.rs` | 205 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/registry.rs` | 442 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker/replacement.rs` | 155 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/credential_broker.rs` | 1,639 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/environment_policy.rs` | 92 | `network-proxy/src/environment_policy.swift` | 🟡 adapted | 策略类型层 |
| `network-proxy/src/http_proxy.rs` | 1,917 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/lib.rs` | 125 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/main.rs` | 119 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/mitm.rs` | 639 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/mitm_hook.rs` | 1,086 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/native_certs.rs` | 260 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/network_policy.rs` | 1,124 | `network-proxy/src/network_policy.swift` | 🟡 adapted | 策略类型层 |
| `network-proxy/src/policy.rs` | 559 | `network-proxy/src/policy.swift` | 🟡 adapted | 策略类型层 |
| `network-proxy/src/process_log_metadata.rs` | 17 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/proxy/execution_scope.rs` | 53 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/proxy.rs` | 3,087 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/reasons.rs` | 9 | `network-proxy/src/reasons.swift` | ✅ faithful | 策略类型层 |
| `network-proxy/src/remote_config.rs` | 119 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/request_cancellation.rs` | 32 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/request_disconnect.rs` | 45 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/responses.rs` | 121 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/runtime.rs` | 2,381 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/socket_path.rs` | 36 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/socks5.rs` | 1,207 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/state.rs` | 460 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/system_dns.rs` | 56 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/upstream.rs` | 286 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/windows_proxy_ingress.rs` | 368 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/windows_tcp_attribution.rs` | 315 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |

## Phase 5

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/compact.rs` | 852 | `compact.swift` | 🟡 adapted | compacted history + insert before last real user; remote V2 stream stays on Session |
| `core/src/compact_model_fallback.rs` | 59 | `compact_model_fallback.swift` | 🟡 adapted |  |
| `core/src/compact_remote_history.rs` | 190 | `compact_remote_history.swift` | 🟡 adapted |  |
| `core/src/compact_remote_v2.rs` | 1,273 | `compact_remote_v2.swift` | 🟡 adapted |  |
| `core/src/compact_remote_v2_attempt.rs` | 133 | `compact_remote_v2_attempt.swift` | 🟡 adapted |  |
| `core/src/compact_remote_v2_images.rs` | 100 | `compact_remote_v2_images.swift` | 🟡 adapted |  |
| `core/src/compact_token_budget.rs` | 84 | `compact_token_budget.swift` | 🟡 adapted |  |
| `core/src/config/auth_keyring.rs` | 122 | `config/auth_keyring.swift` | 🟡 adapted |  |
| `core/src/config/edit/bedrock.rs` | 37 | `config/edit/bedrock.swift` | 🟡 adapted |  |
| `core/src/config/edit/document_helpers.rs` | 343 | `config/edit/document_helpers.swift` | 🟡 adapted |  |
| `core/src/config/edit.rs` | 1,001 | `config/edit.swift` | 🟡 adapted |  |
| `core/src/config/managed_features.rs` | 340 | `config/managed_features.swift` | 🟡 adapted |  |
| `core/src/config/metrics.rs` | 10 | `config/metrics.swift` | 🟡 adapted |  |
| `core/src/config/mod.rs` | 4,893 | `config/config_mod.swift` | 🟡 adapted | TokenBudgetConfig + fallback_buffer_tokens; TOML layers stay out |
| `core/src/config/network_config.rs` | 176 | `config/network_config.swift` | 🟡 adapted |  |
| `core/src/config/network_proxy_spec.rs` | 546 | `config/network_proxy_spec.swift` | 🟡 adapted |  |
| `core/src/config/otel.rs` | 118 | `config/otel.swift` | 🟡 adapted |  |
| `core/src/config/permission_path.rs` | 75 | `config/permission_path.swift` | 🟡 adapted |  |
| `core/src/config/permission_profile_catalog.rs` | 137 | `config/permission_profile_catalog.swift` | 🟡 adapted |  |
| `core/src/config/permission_profile_selection.rs` | 39 | `config/permission_profile_selection.swift` | 🟡 adapted |  |
| `core/src/config/permissions.rs` | 893 | `config/config_permissions.swift` | 🟡 adapted | R4a basename |
| `core/src/config/requirements.rs` | 178 | `config/requirements.swift` | 🟡 adapted |  |
| `core/src/config/resolved_permission_profile.rs` | 93 | `config/resolved_permission_profile.swift` | 🟡 adapted |  |
| `core/src/config/schema.rs` | 7 | `config/schema.swift` | 🟡 adapted |  |
| `core/src/config/token_budget_startup.rs` | 31 | `config/token_budget_startup.swift` | 🟡 adapted |  |
| `core/src/config/windows_sandbox_config.rs` | 126 | `config/windows_sandbox_config.swift` | 🟡 adapted |  |
| `core/src/context/agent_message_board_notification.rs` | 42 | `context/agent_message_board_notification.swift` | 🟡 adapted |  |
| `core/src/context/approved_command_prefix_saved.rs` | 43 | `context/approved_command_prefix_saved.swift` | ✅ faithful |  |
| `core/src/context/apps_instructions.rs` | 33 | `context/apps_instructions.swift` | ✅ faithful |  |
| `core/src/context/available_plugins_instructions.rs` | 49 | `context/available_plugins_instructions.swift` | ✅ faithful |  |
| `core/src/context/base_instructions.rs` | 31 | `context/base_instructions.swift` | ✅ faithful |  |
| `core/src/context/compaction_summary.rs` | 37 | `context/compaction_summary.swift` | ✅ faithful |  |
| `core/src/context/contextual_user_message.rs` | 112 | `context/contextual_user_message.swift` | 🟡 adapted |  |
| `core/src/context/current_time_reminder.rs` | 71 | `context/current_time_reminder.swift` | ✅ faithful |  |
| `core/src/context/developer_instructions.rs` | 37 | `context/developer_instructions.swift` | ✅ faithful |  |
| `core/src/context/environment_context.rs` | 243 | `context/environment_context.swift` | 🟡 adapted |  |
| `core/src/context/environments_instructions.rs` | 38 | `context/environments_instructions.swift` | ✅ faithful |  |
| `core/src/context/guardian_approved_action.rs` | 48 | `context/guardian_approved_action.swift` | 🟡 adapted |  |
| `core/src/context/guardian_budget_omission.rs` | 32 | `context/guardian_budget_omission.swift` | ✅ faithful |  |
| `core/src/context/guardian_context_mode.rs` | 48 | `context/guardian_context_mode.swift` | 🟡 adapted |  |
| `core/src/context/guardian_followup_review_reminder.rs` | 34 | `context/guardian_followup_review_reminder.swift` | ✅ faithful |  |
| `core/src/context/guardian_node_repl_policy.rs` | 39 | `context/guardian_node_repl_policy.swift` | 🟡 adapted |  |
| `core/src/context/guardian_policy.rs` | 42 | `context/guardian_policy.swift` | 🟡 adapted |  |
| `core/src/context/guardian_review_evidence.rs` | 312 | `context/guardian_review_evidence.swift` | 🟡 adapted |  |
| `core/src/context/guardian_sender_messages.rs` | 58 | `context/guardian_sender_messages.swift` | 🟡 adapted |  |
| `core/src/context/guardian_tool_descriptions.rs` | 58 | `context/guardian_tool_descriptions.swift` | 🟡 adapted |  |
| `core/src/context/hook_additional_context.rs` | 35 | `context/hook_additional_context.swift` | ✅ faithful |  |
| `core/src/context/image_resize_notice.rs` | 79 | `context/image_resize_notice.swift` | 🟡 adapted |  |
| `core/src/context/inter_agent_completion_message.rs` | 46 | `context/inter_agent_completion_message.swift` | 🟡 adapted |  |
| `core/src/context/inter_agent_message.rs` | 71 | `context/inter_agent_message.swift` | ✅ faithful |  |
| `core/src/context/internal_model_context.rs` | 134 | `context/internal_model_context.swift` | ✅ faithful |  |
| `core/src/context/legacy_apply_patch_exec_command_warning.rs` | 34 | `context/legacy_apply_patch_exec_command_warning.swift` | ✅ faithful |  |
| `core/src/context/legacy_model_mismatch_warning.rs` | 34 | `context/legacy_model_mismatch_warning.swift` | ✅ faithful |  |
| `core/src/context/legacy_unified_exec_process_limit_warning.rs` | 34 | `context/legacy_unified_exec_process_limit_warning.swift` | ✅ faithful |  |
| `core/src/context/memory.rs` | 43 | `context/memory.swift` | 🟡 adapted |  |
| `core/src/context/mod.rs` | 125 | `context/context_mod.swift` | 🟡 adapted |  |
| `core/src/context/model_switch_instructions.rs` | 44 | `context/model_switch_instructions.swift` | 🟡 adapted |  |
| `core/src/context/multi_agent_mode_instructions.rs` | 54 | `context/multi_agent_mode_instructions.swift` | 🟡 adapted |  |
| `core/src/context/multi_agent_usage_hint.rs` | 42 | `context/multi_agent_usage_hint.swift` | 🟡 adapted |  |
| `core/src/context/network_rule_saved.rs` | 48 | `context/network_rule_saved.swift` | 🟡 adapted |  |
| `core/src/context/node_repl_review_evidence.rs` | 316 | `context/node_repl_review_evidence.swift` | 🟡 adapted |  |
| `core/src/context/plugin_instructions.rs` | 35 | `context/plugin_instructions.swift` | ✅ faithful |  |
| `core/src/context/recommended_plugins_instructions.rs` | 55 | `context/recommended_plugins_instructions.swift` | 🟡 adapted |  |
| `core/src/context/rollout_budget.rs` | 32 | `context/context_rollout_budget.swift` | ✅ faithful |  |
| `core/src/context/subagent_notification.rs` | 47 | `context/subagent_notification.swift` | 🟡 adapted |  |
| `core/src/context/token_budget_context.rs` | 245 | `context/token_budget_context.swift` | 🟡 adapted |  |
| `core/src/context/turn_aborted.rs` | 40 | `context/turn_aborted.swift` | ✅ faithful |  |
| `core/src/context/unsupported_media.rs` | 42 | `context/unsupported_media.swift` | ✅ faithful |  |
| `core/src/context/user_instructions.rs` | 35 | `context/user_instructions.swift` | ✅ faithful |  |
| `core/src/context/user_shell_command.rs` | 53 | `context/context_user_shell_command.swift` | ✅ faithful |  |
| `core/src/context/user_verification_notice.rs` | 28 | `context/user_verification_notice.swift` | ✅ faithful |  |
| `core/src/context/world_state/agents_md.rs` | 84 | `context/world_state/agents_md.swift` | 🟡 adapted |  |
| `core/src/context/world_state/apps_instructions.rs` | 55 | `context/world_state/world_state_apps_instructions.swift` | 🟡 adapted |  |
| `core/src/context/world_state/collaboration_mode.rs` | 177 | `context/world_state/collaboration_mode.swift` | 🟡 adapted |  |
| `core/src/context/world_state/compact_permissions.rs` | 59 | `context/world_state/compact_permissions.swift` | 🟡 adapted |  |
| `core/src/context/world_state/context_window_guidance.rs` | 76 | `context/world_state/context_window_guidance.swift` | 🟡 adapted |  |
| `core/src/context/world_state/environment.rs` | 557 | `context/world_state/environment.swift` | 🟡 adapted |  |
| `core/src/context/world_state/environments_instructions.rs` | 55 | `context/world_state/world_state_environments_instructions.swift` | 🟡 adapted |  |
| `core/src/context/world_state/managed_developer_instructions.rs` | 157 | `context/world_state/managed_developer_instructions.swift` | 🟡 adapted |  |
| `core/src/context/world_state/mod.rs` | 556 | `context/world_state/world_state_mod.swift` | 🟡 adapted | snapshot + renderDiff/renderFull; SHA-1 hashing stays out |
| `core/src/context/world_state/model.rs` | 65 | `context/world_state/model.swift` | 🟡 adapted |  |
| `core/src/context/world_state/multi_agent_mode.rs` | 91 | `context/world_state/multi_agent_mode.swift` | 🟡 adapted |  |
| `core/src/context/world_state/multi_agent_usage_hint.rs` | 50 | `context/world_state/world_state_multi_agent_usage_hint.swift` | 🟡 adapted |  |
| `core/src/context/world_state/permissions.rs` | 131 | `context/world_state/permissions.swift` | 🟡 adapted |  |
| `core/src/context/world_state/persistent_mode.rs` | 120 | `context/world_state/persistent_mode.swift` | 🟡 adapted |  |
| `core/src/context/world_state/plugins_instructions.rs` | 55 | `context/world_state/plugins_instructions.swift` | 🟡 adapted |  |
| `core/src/context/world_state/realtime.rs` | 96 | `context/world_state/realtime.swift` | 🟡 adapted |  |
| `core/src/context/world_state/tools.rs` | 170 | `context/world_state/tools.swift` | 🟡 adapted |  |
| `core/src/context_manager/history.rs` | 1,225 | `context_manager/history.swift` | 🟡 adapted |  |
| `core/src/context_manager/history_user_authorization.rs` | 105 | `context_manager/history_user_authorization.swift` | 🟡 adapted |  |
| `core/src/context_manager/mod.rs` | 9 | `context_manager/context_manager_mod.swift` | ✅ faithful |  |
| `core/src/context_manager/normalize.rs` | 420 | `context_manager/normalize.swift` | 🟡 adapted |  |
| `core/src/context_manager/updates.rs` | 60 | `context_manager/updates.swift` | 🟡 adapted |  |
| `core/src/event_mapping.rs` | 261 | `event_mapping.swift` | 🟡 adapted |  |
| `core/src/mcp.rs` | 394 | `mcp.swift` | 🟡 adapted |  |
| `core/src/mcp_openai_file.rs` | 698 | `mcp_openai_file.swift` | 🟡 adapted |  |
| `core/src/mcp_skill_dependencies.rs` | 531 | `mcp_skill_dependencies.swift` | 🟡 adapted |  |
| `core/src/mcp_tool_approval_templates.rs` | 371 | `mcp_tool_approval_templates.swift` | 🟡 adapted |  |
| `core/src/mcp_tool_call/account.rs` | 39 | `mcp_tool_call/account.swift` | 🟡 adapted |  |
| `core/src/mcp_tool_call/telemetry.rs` | 166 | `mcp_tool_call/telemetry.swift` | 🟡 adapted |  |
| `core/src/mcp_tool_call.rs` | 2,504 | `mcp_tool_call.swift` | 🟡 adapted |  |
| `core/src/mcp_tool_exposure.rs` | 189 | `mcp_tool_exposure.swift` | 🟡 adapted | Apps omit/visibility/budget + binding generation cache |
| `core/src/session/code_mode_warning.rs` | 26 | `session/code_mode_warning.swift` | 🟡 adapted |  |
| `core/src/session/context_window.rs` | 130 | `session/context_window.swift` | 🟡 adapted | fallback buffer from TokenBudgetConfig when a prompt is set |
| `core/src/session/daemon_recovery.rs` | 46 | `session/daemon_recovery.swift` | 🟡 adapted |  |
| `core/src/session/environment.rs` | 307 | `session/environment.swift` | 🟡 adapted |  |
| `core/src/session/extension_interruption.rs` | 117 | `session/extension_interruption.swift` | 🟡 adapted |  |
| `core/src/session/extension_metrics.rs` | 35 | `session/extension_metrics.swift` | 🟡 adapted |  |
| `core/src/session/guardian_checkpoint.rs` | 47 | `session/guardian_checkpoint.swift` | 🟡 adapted |  |
| `core/src/session/handlers.rs` | 681 | `session/handlers.swift` | 🟡 adapted |  |
| `core/src/session/inject.rs` | 193 | `session/inject.swift` | 🟡 adapted |  |
| `core/src/session/input_queue.rs` | 669 | `session/input_queue.swift` | 🟡 adapted | mailbox/steer activity watch; gauges omitted |
| `core/src/session/mcp.rs` | 1,206 | `session/session_mcp.swift` | 🟡 adapted |  |
| `core/src/session/mcp_prewarm.rs` | 82 | `session/mcp_prewarm.swift` | 🟡 adapted |  |
| `core/src/session/mcp_refresh.rs` | 56 | `session/mcp_refresh.swift` | 🟡 adapted |  |
| `core/src/session/mcp_runtime.rs` | 381 | `session/mcp_runtime.swift` | 🟡 adapted |  |
| `core/src/session/mod.rs` | 5,130 | `session/session_mod.swift` | 🟡 adapted |  |
| `core/src/session/plugin_selection.rs` | 32 | `session/plugin_selection.swift` | 🟡 adapted |  |
| `core/src/session/reasoning_effort.rs` | 162 | `session/reasoning_effort.swift` | 🟡 adapted |  |
| `core/src/session/retained_context.rs` | 35 | `session/retained_context.swift` | 🟡 adapted |  |
| `core/src/session/review.rs` | 229 | `session/session_review.swift` | 🟡 adapted |  |
| `core/src/session/rollout_budget.rs` | 34 | `session/rollout_budget.swift` | 🟡 adapted |  |
| `core/src/session/rollout_reconstruction.rs` | 575 | `session/rollout_reconstruction.swift` | 🟡 adapted |  |
| `core/src/session/session.rs` | 1,915 | `session/session.swift` | 🟡 adapted | emitTurnStarted + startup prewarm consume + MCP reprojection |
| `core/src/session/startup.rs` | 37 | `session/startup.swift` | 🟡 adapted |  |
| `core/src/session/step_activation.rs` | 472 | `session/step_activation.swift` | 🟡 adapted |  |
| `core/src/session/step_context.rs` | 57 | `session/step_context.swift` | 🟡 adapted |  |
| `core/src/session/step_settings.rs` | 347 | `session/step_settings.swift` | 🟡 adapted |  |
| `core/src/session/submission.rs` | 18 | `session/submission.swift` | 🟡 adapted |  |
| `core/src/session/thread_settings.rs` | 152 | `session/thread_settings.swift` | 🟡 adapted |  |
| `core/src/session/time_reminder.rs` | 202 | `session/time_reminder.swift` | 🟡 adapted |  |
| `core/src/session/token_budget.rs` | 248 | `session/token_budget.swift` | 🟡 adapted | inline compact + resolveTokenBudgetConfig; experimental ChatGPT eligibility stays out |
| `core/src/session/turn.rs` | 3,105 | `session/turn.swift` | 🟡 adapted | assembleToolRouter: Apps/visibility/budget + Sage execute tools |
| `core/src/session/turn_context.rs` | 1,386 | `session/turn_context.swift` | 🟡 adapted |  |
| `core/src/session/turn_input.rs` | 765 | `session/turn_input.swift` | 🟡 adapted |  |
| `core/src/session/turn_suspension.rs` | 119 | `session/turn_suspension.swift` | 🟡 adapted |  |
| `core/src/session/world_state.rs` | 295 | `session/world_state.swift` | 🟡 adapted | step snapshot + compact reinject + exec-policy prefixes; plugin contributors stay out |
| `core/src/session_startup_prewarm.rs` | 328 | `session_startup_prewarm.swift` | 🟡 adapted |  |
| `core/src/state/additional_context.rs` | 35 | `state/additional_context.swift` | ✅ faithful |  |
| `core/src/state/auto_compact_window.rs` | 237 | `state/auto_compact_window.swift` | ✅ faithful |  |
| `core/src/state/mod.rs` | 22 | `state/state_mod.swift` | ✅ faithful |  |
| `core/src/state/service.rs` | 104 | `state/service.swift` | 🟡 adapted |  |
| `core/src/state/session.rs` | 475 | `state/state_session.swift` | 🟡 adapted |  |
| `core/src/state/turn.rs` | 254 | `state/state_turn.swift` | 🟡 adapted |  |
| `core/src/state/turn_token_usage.rs` | 48 | `state/turn_token_usage.swift` | 🟡 adapted |  |
| `core/src/stream_events_utils.rs` | 586 | `stream_events_utils.swift` | 🟡 adapted |  |
| `core/src/tasks/compact.rs` | 76 | `tasks/compact.swift` | 🟡 adapted | token-budget window reset + occupancy share CompactTokenBudget; remote V2 stays on runAutoCompact |
| `core/src/tasks/lifecycle.rs` | 119 | `tasks/tasks_lifecycle.swift` | 🟡 adapted |  |
| `core/src/tasks/mod.rs` | 1,014 | `tasks/tasks_mod.swift` | 🟡 adapted | spawnTask / startTask / onTaskFinished / abortAllTasks |
| `core/src/tasks/regular.rs` | 126 | `tasks/regular.swift` | 🟡 adapted | provider text streams into runTurn; function calls wait for HUD admission |
| `core/src/tasks/review.rs` | 280 | `tasks/tasks_review.swift` | 🟡 adapted |  |
| `core/src/tasks/user_shell.rs` | 485 | `tasks/user_shell.swift` | 🟡 adapted |  |
| `core/src/turn_diff_tracker.rs` | 403 | `turn_diff_tracker.swift` | 🟡 adapted |  |
| `core/src/turn_metadata.rs` | 569 | `turn_metadata.swift` | 🟡 adapted |  |
| `core/src/turn_timing.rs` | 443 | `turn_timing.swift` | 🟡 adapted |  |

## Phase 6

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/client.rs` | 2,852 | `client.swift` | 🟡 adapted | prepareResponseItemsForRequest strips unprefixed ids and content-item kinds |
| `core/src/client_common.rs` | 141 | `client_common.swift` | 🟡 adapted |  |
| `core/src/current_time.rs` | 55 | `current_time.swift` | 🟡 adapted |  |
| `core/src/image_preparation.rs` | 428 | `image_preparation.swift` | 🟡 adapted |  |
| `core/src/original_image_detail.rs` | 2 | `original_image_detail.swift` | ✅ faithful |  |
| `core/src/prompt_debug.rs` | 114 | `prompt_debug.swift` | 🟡 adapted |  |
| `core/src/responses_headers.rs` | 24 | `responses_headers.swift` | 🟡 adapted |  |
| `core/src/responses_metadata.rs` | 592 | `responses_metadata.swift` | 🟡 adapted |  |
| `core/src/responses_retry.rs` | 180 | `responses_retry.swift` | 🟡 adapted |  |
| `core/src/web_search.rs` | 30 | `web_search.swift` | ✅ faithful |  |
| `codex-api/src/api_bridge.rs` | 318 | `codex-api/src/api_bridge.swift` | 🟡 adapted |  |
| `codex-api/src/auth.rs` | 104 | `codex-api/src/auth.swift` | 🟡 adapted |  |
| `codex-api/src/common.rs` | 406 | `codex-api/src/common.swift` | 🟡 adapted |  |
| `codex-api/src/endpoint/images.rs` | 403 | `codex-api/src/endpoint/endpoint_images.swift` | 🟡 adapted |  |
| `codex-api/src/endpoint/memories.rs` | 225 | `codex-api/src/endpoint/memories.swift` | 🟡 adapted |  |
| `codex-api/src/endpoint/mod.rs` | 34 | `codex-api/src/endpoint/endpoint_mod.swift` | 🟡 adapted |  |
| `codex-api/src/endpoint/models.rs` | 431 | `codex-api/src/endpoint/models.swift` | 🟡 adapted |  |
| `codex-api/src/endpoint/realtime_call.rs` | 796 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/methods.rs` | 3,225 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/methods_common.rs` | 179 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/methods_frameless_bidi.rs` | 129 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/methods_v1.rs` | 83 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/methods_v2.rs` | 180 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/mod.rs` | 22 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/protocol.rs` | 272 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/protocol_common.rs` | 83 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/protocol_frameless_bidi.rs` | 99 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/protocol_v1.rs` | 99 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/realtime_websocket/protocol_v2.rs` | 210 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/responses.rs` | 159 | `codex-api/src/endpoint/endpoint_responses.swift` | 🟡 adapted |  |
| `codex-api/src/endpoint/responses_websocket.rs` | 1,241 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/search.rs` | 320 | `codex-api/src/endpoint/endpoint_search.swift` | 🟡 adapted |  |
| `codex-api/src/endpoint/session.rs` | 156 | `codex-api/src/endpoint/session.swift` | 🟡 adapted |  |
| `codex-api/src/error.rs` | 55 | `codex-api/src/error.swift` | 🟡 adapted |  |
| `codex-api/src/files.rs` | 887 | `codex-api/src/files.swift` | 🟡 adapted |  |
| `codex-api/src/images.rs` | 72 | `codex-api/src/images.swift` | ✅ faithful |  |
| `codex-api/src/lib.rs` | 121 | `codex-api/src/lib.swift` | 🟡 adapted |  |
| `codex-api/src/provider.rs` | 166 | `codex-api/src/provider.swift` | 🟡 adapted |  |
| `codex-api/src/rate_limits.rs` | 382 | `codex-api/src/rate_limits.swift` | 🟡 adapted |  |
| `codex-api/src/requests/headers.rs` | 40 | `codex-api/src/requests/headers.swift` | 🟡 adapted |  |
| `codex-api/src/requests/mod.rs` | 4 | `codex-api/src/requests/requests_mod.swift` | 🟡 adapted |  |
| `codex-api/src/requests/responses.rs` | 6 | `codex-api/src/requests/requests_responses.swift` | 🟡 adapted |  |
| `codex-api/src/safety_buffering.rs` | 67 | `codex-api/src/safety_buffering.swift` | 🟡 adapted |  |
| `codex-api/src/search.rs` | 305 | `codex-api/src/search.swift` | ✅ faithful |  |
| `codex-api/src/sse/mod.rs` | 5 | `codex-api/src/sse/sse_mod.swift` | 🟡 adapted |  |
| `codex-api/src/sse/responses.rs` | 2,124 | `codex-api/src/sse/responses.swift` | 🟡 adapted |  |
| `codex-api/src/telemetry.rs` | 98 | `codex-api/src/telemetry.swift` | 🟡 adapted |  |
| `model-provider-info/src/gateway_oauth.rs` | 157 | `model-provider-info/src/gateway_oauth.swift` | 🟡 adapted |  |
| `model-provider-info/src/lib.rs` | 767 | `model-provider-info/src/lib.swift` | 🟡 adapted |  |

## Phase 7

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/attestation.rs` | 26 | `attestation.swift` | 🟡 adapted |  |
| `core/src/codex_delegate.rs` | 382 | `codex_delegate.swift` | 🟡 adapted |  |
| `core/src/codex_thread.rs` | 1,065 | `codex_thread.swift` | 🟡 adapted |  |
| `core/src/feedback_config.rs` | 81 | `feedback_config.swift` | 🟡 adapted |  |
| `core/src/installation_id.rs` | 149 | `installation_id.swift` | 🟡 adapted |  |
| `core/src/memory_usage.rs` | 51 | `memory_usage.swift` | 🟡 adapted |  |
| `core/src/rollout.rs` | 61 | `rollout.swift` | 🟡 adapted |  |
| `core/src/rollout_budget.rs` | 121 | `rollout_budget.swift` | 🟡 adapted |  |
| `core/src/session_prefix.rs` | 50 | `session_prefix.swift` | 🟡 adapted |  |
| `core/src/session_rollout_init_error.rs` | 67 | `session_rollout_init_error.swift` | 🟡 adapted |  |
| `core/src/state_db_bridge.rs` | 8 | `state_db_bridge.swift` | 🟡 adapted |  |
| `core/src/thread_manager/managed.rs` | 109 | `thread_manager/managed.swift` | 🟡 adapted |  |
| `core/src/thread_manager/shared_instructions.rs` | 112 | `thread_manager/shared_instructions.swift` | 🟡 adapted |  |
| `core/src/thread_manager.rs` | 2,583 | `thread_manager.swift` | 🟡 adapted |  |
| `core/src/thread_rollout_truncation.rs` | 305 | `thread_rollout_truncation.swift` | 🟡 adapted |  |
| `core/src/thread_startup_metadata.rs` | 110 | `thread_startup_metadata.swift` | 🟡 adapted |  |
| `rollout/src/compression/error_metrics.rs` | 65 | `rollout/src/compression/error_metrics.swift` | 🟡 adapted |  |
| `rollout/src/compression/read_metrics.rs` | 58 | `rollout/src/compression/read_metrics.swift` | 🟡 adapted |  |
| `rollout/src/compression.rs` | 1,403 | `rollout/src/compression.swift` | 🟡 adapted |  |
| `rollout/src/config.rs` | 101 | `rollout/src/config.swift` | 🟡 adapted |  |
| `rollout/src/lib.rs` | 171 | `rollout/src/lib.swift` | 🟡 adapted |  |
| `rollout/src/list.rs` | 1,703 | `rollout/src/list.swift` | 🟡 adapted |  |
| `rollout/src/maintenance.rs` | 41 | `rollout/src/maintenance.swift` | 🟡 adapted |  |
| `rollout/src/metadata.rs` | 491 | `rollout/src/metadata.swift` | 🟡 adapted |  |
| `rollout/src/model_context.rs` | 59 | `rollout/src/model_context.swift` | ✅ faithful |  |
| `rollout/src/ordinal.rs` | 131 | `rollout/src/ordinal.swift` | 🟡 adapted |  |
| `rollout/src/persistence_metrics.rs` | 439 | `rollout/src/persistence_metrics.swift` | 🟡 adapted |  |
| `rollout/src/policy.rs` | 206 | `rollout/src/policy.swift` | 🟡 adapted |  |
| `rollout/src/recorder.rs` | 2,249 | `rollout/src/recorder.swift` | 🟡 adapted |  |
| `rollout/src/reverse_jsonl_scanner.rs` | 165 | `rollout/src/reverse_jsonl_scanner.swift` | ✅ faithful |  |
| `rollout/src/rollout_file_name.rs` | 87 | `rollout/src/rollout_file_name.swift` | 🟡 adapted |  |
| `rollout/src/rollout_reference_index.rs` | 168 | `rollout/src/rollout_reference_index.swift` | 🟡 adapted |  |
| `rollout/src/search.rs` | 370 | `rollout/src/search.swift` | 🟡 adapted |  |
| `rollout/src/seekable_reader.rs` | 110 | `rollout/src/seekable_reader.swift` | 🟡 adapted |  |
| `rollout/src/session_index.rs` | 300 | `rollout/src/session_index.swift` | 🟡 adapted |  |
| `rollout/src/sqlite_metrics.rs` | 73 | `rollout/src/sqlite_metrics.swift` | 🟡 adapted |  |
| `rollout/src/state_db.rs` | 744 | `rollout/src/state_db.swift` | 🟡 adapted |  |
| `rollout/src/writer_lock.rs` | 200 | `rollout/src/writer_lock.swift` | 🟡 adapted |  |
| `state/src/audit.rs` | 48 | `state/src/audit.swift` | 🟡 adapted |  |
| `state/src/extract.rs` | 850 | `state/src/extract.swift` | 🟡 adapted |  |
| `state/src/lib.rs` | 152 | `state/src/lib.swift` | 🟡 adapted |  |
| `state/src/log_db.rs` | 884 | `state/src/log_db.swift` | 🟡 adapted |  |
| `state/src/migrations.rs` | 122 | `state/src/migrations.swift` | 🟡 adapted |  |
| `state/src/model/backfill_state.rs` | 73 | `state/src/model/backfill_state.swift` | 🟡 adapted |  |
| `state/src/model/graph.rs` | 11 | `state/src/model/graph.swift` | ✅ faithful |  |
| `state/src/model/log.rs` | 57 | `state/src/model/log.swift` | 🟡 adapted |  |
| `state/src/model/memories.rs` | 69 | `state/src/model/memories.swift` | 🟡 adapted |  |
| `state/src/model/mod.rs` | 56 | `state/src/model/mod.swift` | ✅ faithful |  |
| `state/src/model/project.rs` | 39 | `state/src/model/project.swift` | ✅ faithful |  |
| `state/src/model/queued_item.rs` | 22 | `state/src/model/queued_item.swift` | 🟡 adapted |  |
| `state/src/model/rollout_migration_state.rs` | 67 | `state/src/model/rollout_migration_state.swift` | 🟡 adapted |  |
| `state/src/model/thread_attachment.rs` | 48 | `state/src/model/thread_attachment.swift` | 🟡 adapted |  |
| `state/src/model/thread_goal.rs` | 117 | `state/src/model/thread_goal.swift` | 🟡 adapted |  |
| `state/src/model/thread_metadata.rs` | 894 | `state/src/model/thread_metadata.swift` | 🟡 adapted |  |
| `state/src/paths.rs` | 9 | `state/src/paths.swift` | ✅ faithful |  |
| `state/src/runtime/backfill.rs` | 288 | `state/src/runtime/backfill.swift` | 🟡 adapted |  |
| `state/src/runtime/external_agent_config_imports.rs` | 148 | `state/src/runtime/external_agent_config_imports.swift` | 🟡 adapted |  |
| `state/src/runtime/goals.rs` | 1,728 | `state/src/runtime/goals.swift` | 🟡 adapted |  |
| `state/src/runtime/logs.rs` | 1,915 | `state/src/runtime/logs.swift` | 🟡 adapted |  |
| `state/src/runtime/memories.rs` | 5,468 | `state/src/runtime/runtime_memories.swift` | 🟡 adapted |  |
| `state/src/runtime/memory_readiness.rs` | 16 | `state/src/runtime/memory_readiness.swift` | 🟡 adapted |  |
| `state/src/runtime/memory_versions.rs` | 56 | `state/src/runtime/memory_versions.swift` | 🟡 adapted |  |
| `state/src/runtime/projects.rs` | 573 | `state/src/runtime/projects.swift` | 🟡 adapted |  |
| `state/src/runtime/queued_items.rs` | 215 | `state/src/runtime/queued_items.swift` | 🟡 adapted |  |
| `state/src/runtime/recovery.rs` | 243 | `state/src/runtime/recovery.swift` | 🟡 adapted |  |
| `state/src/runtime/remote_control.rs` | 393 | `state/src/runtime/remote_control.swift` | 🟡 adapted |  |
| `state/src/runtime/rollout_migration.rs` | 149 | `state/src/runtime/rollout_migration.swift` | 🟡 adapted |  |
| `state/src/runtime/test_support.rs` | 84 | `state/src/runtime/test_support.swift` | 🟡 adapted |  |
| `state/src/runtime/thread_attachments.rs` | 291 | `state/src/runtime/thread_attachments.swift` | 🟡 adapted |  |
| `state/src/runtime/thread_section_order.rs` | 284 | `state/src/runtime/thread_section_order.swift` | 🟡 adapted |  |
| `state/src/runtime/thread_sections.rs` | 93 | `state/src/runtime/thread_sections.swift` | 🟡 adapted |  |
| `state/src/runtime/threads.rs` | 3,637 | `state/src/runtime/threads.swift` | 🟡 adapted |  |
| `state/src/runtime.rs` | 764 | `state/src/runtime.swift` | 🟡 adapted |  |
| `state/src/sqlite.rs` | 332 | `state/src/sqlite.swift` | 🟡 adapted |  |
| `state/src/telemetry.rs` | 251 | `state/src/telemetry.swift` | 🟡 adapted |  |
| `thread-store/src/error.rs` | 55 | `thread-store/src/error.swift` | 🟡 adapted |  |
| `thread-store/src/in_memory.rs` | 1,204 | `thread-store/src/in_memory.swift` | 🟡 adapted |  |
| `thread-store/src/lib.rs` | 114 | `thread-store/src/lib.swift` | 🟡 adapted |  |
| `thread-store/src/live_thread.rs` | 463 | `thread-store/src/live_thread.swift` | 🟡 adapted |  |
| `thread-store/src/local/archive_thread.rs` | 371 | `thread-store/src/local/archive_thread.swift` | 🟡 adapted |  |
| `thread-store/src/local/create_thread.rs` | 68 | `thread-store/src/local/create_thread.swift` | 🟡 adapted |  |
| `thread-store/src/local/delete_thread.rs` | 883 | `thread-store/src/local/delete_thread.swift` | 🟡 adapted |  |
| `thread-store/src/local/helpers.rs` | 385 | `thread-store/src/local/helpers.swift` | 🟡 adapted |  |
| `thread-store/src/local/list_threads.rs` | 793 | `thread-store/src/local/list_threads.swift` | 🟡 adapted |  |
| `thread-store/src/local/live_writer.rs` | 374 | `thread-store/src/local/live_writer.swift` | 🟡 adapted |  |
| `thread-store/src/local/mod.rs` | 2,137 | `thread-store/src/local/mod.swift` | 🟡 adapted |  |
| `thread-store/src/local/model_context.rs` | 193 | `thread-store/src/local/model_context.swift` | 🟡 adapted |  |
| `thread-store/src/local/move_thread_to_section.rs` | 58 | `thread-store/src/local/move_thread_to_section.swift` | 🟡 adapted |  |
| `thread-store/src/local/paginated_fork.rs` | 191 | `thread-store/src/local/paginated_fork.swift` | 🟡 adapted |  |
| `thread-store/src/local/pending_thread_metadata.rs` | 58 | `thread-store/src/local/pending_thread_metadata.swift` | 🟡 adapted |  |
| `thread-store/src/local/projects.rs` | 192 | `thread-store/src/local/local_projects.swift` | 🟡 adapted |  |
| `thread-store/src/local/read_thread.rs` | 1,641 | `thread-store/src/local/read_thread.swift` | 🟡 adapted |  |
| `thread-store/src/local/revert_thread.rs` | 208 | `thread-store/src/local/revert_thread.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_lineage.rs` | 304 | `thread-store/src/local/rollout_lineage.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/canonicalizer.rs` | 502 | `thread-store/src/local/rollout_migration/canonicalizer.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/legacy_event.rs` | 313 | `thread-store/src/local/rollout_migration/legacy_event.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/line_parser.rs` | 201 | `thread-store/src/local/rollout_migration/line_parser.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/publish.rs` | 267 | `thread-store/src/local/rollout_migration/publish.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/rollback.rs` | 147 | `thread-store/src/local/rollout_migration/rollback.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/rollback_plan.rs` | 541 | `thread-store/src/local/rollout_migration/rollback_plan.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/rollback_replay.rs` | 195 | `thread-store/src/local/rollout_migration/rollback_replay.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/startup.rs` | 412 | `thread-store/src/local/rollout_migration/startup.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/subagent.rs` | 55 | `thread-store/src/local/rollout_migration/subagent.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration/telemetry.rs` | 152 | `thread-store/src/local/rollout_migration/telemetry.swift` | 🟡 adapted |  |
| `thread-store/src/local/rollout_migration.rs` | 1,386 | `thread-store/src/local/rollout_migration.swift` | 🟡 adapted |  |
| `thread-store/src/local/search_threads.rs` | 257 | `thread-store/src/local/search_threads.swift` | 🟡 adapted |  |
| `thread-store/src/local/test_support.rs` | 131 | `thread-store/src/local/test_support.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_attachments.rs` | 116 | `thread-store/src/local/local_thread_attachments.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_history/read.rs` | 432 | `thread-store/src/local/thread_history/read.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_history/realtime.rs` | 246 | `thread-store/src/local/thread_history/realtime.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_history/search.rs` | 494 | `thread-store/src/local/thread_history/search.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_history/segment_paging.rs` | 506 | `thread-store/src/local/thread_history/segment_paging.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_history/turn_lookup.rs` | 100 | `thread-store/src/local/thread_history/turn_lookup.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_history.rs` | 579 | `thread-store/src/local/thread_history.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_history_materialization.rs` | 366 | `thread-store/src/local/thread_history_materialization.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_rollout_resolver.rs` | 216 | `thread-store/src/local/thread_rollout_resolver.swift` | 🟡 adapted |  |
| `thread-store/src/local/thread_sections.rs` | 99 | `thread-store/src/local/local_thread_sections.swift` | 🟡 adapted |  |
| `thread-store/src/local/unarchive_thread.rs` | 286 | `thread-store/src/local/unarchive_thread.swift` | 🟡 adapted |  |
| `thread-store/src/local/update_thread_metadata.rs` | 2,431 | `thread-store/src/local/update_thread_metadata.swift` | 🟡 adapted |  |
| `thread-store/src/projects.rs` | 81 | `thread-store/src/projects.swift` | 🟡 adapted |  |
| `thread-store/src/queue_store.rs` | 158 | `thread-store/src/queue_store.swift` | 🟡 adapted |  |
| `thread-store/src/store.rs` | 554 | `thread-store/src/store.swift` | 🟡 adapted |  |
| `thread-store/src/thread_attachments.rs` | 39 | `thread-store/src/thread_attachments.swift` | 🟡 adapted |  |
| `thread-store/src/thread_metadata_sync.rs` | 928 | `thread-store/src/thread_metadata_sync.swift` | 🟡 adapted |  |
| `thread-store/src/thread_sections.rs` | 52 | `thread-store/src/thread_sections.swift` | 🟡 adapted |  |
| `thread-store/src/types.rs` | 1,127 | `thread-store/src/types.swift` | 🟡 adapted |  |

## Phase 8

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/agents_md.rs` | 562 | `core_agents_md.swift` | 🟡 adapted |  |
| `core/src/agents_md_manager.rs` | 182 | `agents_md_manager.swift` | 🟡 adapted |  |
| `core/src/elicitation.rs` | 100 | `elicitation.swift` | ✅ faithful |  |
| `core/src/guardian/approval_request.rs` | 564 | `guardian/approval_request.swift` | 🟡 adapted | live HUD kinds + pretty; assessment JSON / analytics stay out |
| `core/src/guardian/coverage.rs` | 33 | `guardian/coverage.swift` | ✅ faithful |  |
| `core/src/guardian/decision.rs` | 132 | `guardian/decision.swift` | 🟡 adapted | live HUD batches consult decide; nil still falls to the card |
| `core/src/guardian/feedback.rs` | 44 | `guardian/feedback.swift` | ✅ faithful |  |
| `core/src/guardian/input_budget.rs` | 197 | `guardian/input_budget.swift` | 🟡 adapted |  |
| `core/src/guardian/mod.rs` | 208 | `guardian/guardian_mod.swift` | 🟡 adapted | R4a basename |
| `core/src/guardian/permissions.rs` |  | `guardian/guardian_permissions.swift` | 🟡 adapted | R4a basename |
| `core/src/guardian/prompt.rs` | 365 | `guardian/prompt.swift` | 🟡 adapted | ACTION + truncated transcript; composed sections stay out |
| `core/src/guardian/request_budget.rs` | 90 | `guardian/request_budget.swift` | 🟡 adapted |  |
| `core/src/guardian/review.rs` | 287 | `guardian/review.swift` | 🟡 adapted | source-kind + project/retry routing; isolated session spawn still thin |
| `core/src/guardian/review_request.rs` | 224 | `guardian/review_request.swift` | 🟡 adapted | routes_approval_policy_to_guardian + project/retry; host prepare stays out |
| `core/src/guardian/review_session.rs` | 947 | `guardian/review_session.swift` | 🟡 adapted | isolated complete + MAX_REVIEW_ATTEMPTS parse retry; trunk/fork spawn stays out |
| `core/src/guardian/review_session_context.rs` | 73 | `guardian/review_session_context.swift` | 🟡 adapted | live transcript slice; checkpoint policy stays out |
| `core/src/guardian/review_session_setup.rs` | 265 | `guardian/review_session_setup.swift` | 🟡 adapted | prompt assemble from reviewer config; session spawn / prewarm stay out |
| `core/src/guardian/reviewer_config.rs` | 109 | `guardian/reviewer_config.swift` | 🟡 adapted | review-role + extra policy + live network; catalog prewarm stays out |
| `core/src/guardian/runtime.rs` | 92 | `guardian/runtime.swift` | 🟡 adapted | ReviewAction + validate + ReviewRuntime.decide; session spawn / cancel stay out |
| `core/src/guardian_review.rs` | 7 | `guardian_review.swift` | 🟡 adapted |  |
| `core/src/hook_mcp_executor.rs` | 57 | `hook_mcp_executor.swift` | 🟡 adapted |  |
| `core/src/hook_runtime.rs` | 1,352 | `hook_runtime.swift` | 🟡 adapted | interrupt + arg match + CommandHookRuntime `run`; MCP execute stays out |
| `core/src/mention_syntax.rs` | 2 | `mention_syntax.swift` | ✅ faithful |  |
| `core/src/skills.rs` | 210 | `skills.swift` | 🟡 adapted |  |
| `agent-roles/src/agent_role_config.rs` | 209 | `agent-roles/src/agent_role_config.swift` | 🟡 adapted |  |
| `agent-roles/src/discovery.rs` | 40 | `agent-roles/src/discovery.swift` | ✅ faithful |  |
| `agent-roles/src/lib.rs` | 8 | `agent-roles/src/lib.swift` | ✅ faithful |  |
| `agent-roles/src/loader.rs` | 335 | `agent-roles/src/loader.swift` | 🟡 adapted |  |
| `context-fragments/src/additional_context.rs` | 102 | `context-fragments/src/additional_context.swift` | ✅ faithful |  |
| `context-fragments/src/annotated_content.rs` | 98 | `context-fragments/src/annotated_content.swift` | ✅ faithful |  |
| `context-fragments/src/answered_question.rs` | 60 | `context-fragments/src/answered_question.swift` | ✅ faithful |  |
| `context-fragments/src/fragment.rs` | 135 | `context-fragments/src/fragment.swift` | ✅ faithful |  |
| `context-fragments/src/lib.rs` | 16 | `context-fragments/src/lib.swift` | ✅ faithful |  |
| `context-fragments/src/recap_prompt.rs` | 67 | `context-fragments/src/recap_prompt.swift` | ✅ faithful |  |
| `hooks/src/bin/write_hooks_schema_fixtures.rs` | 9 | - | ⛔ excluded | CLI fixture writer; Sage does not generate schema fixtures |
| `hooks/src/config_rules.rs` | 259 | `hooks/src/config_rules.swift` | 🟡 adapted |  |
| `hooks/src/declarations.rs` | 102 | `hooks/src/declarations.swift` | 🟡 adapted |  |
| `hooks/src/engine/command_runner.rs` | 466 | `hooks/src/engine/command_runner.swift` | 🟡 adapted |  |
| `hooks/src/engine/discovery.rs` | 1,741 | `hooks/src/engine/discovery.swift` | 🟡 adapted |  |
| `hooks/src/engine/dispatcher.rs` | 656 | `hooks/src/engine/dispatcher.swift` | 🟡 adapted |  |
| `hooks/src/engine/mcp_runner.rs` | 166 | `hooks/src/engine/mcp_runner.swift` | 🟡 adapted |  |
| `hooks/src/engine/mod.rs` | 492 | `hooks/src/engine/engine_mod.swift` | 🟡 adapted |  |
| `hooks/src/engine/output_parser.rs` | 617 | `hooks/src/engine/output_parser.swift` | 🟡 adapted |  |
| `hooks/src/engine/schema_loader.rs` | 168 | `hooks/src/engine/schema_loader.swift` | 🟡 adapted |  |
| `hooks/src/events/common.rs` | 306 | `hooks/src/events/common.swift` | ✅ faithful |  |
| `hooks/src/events/compact.rs` | 554 | `hooks/src/events/compact.swift` | 🟡 adapted |  |
| `hooks/src/events/interrupt.rs` | 183 | `hooks/src/events/interrupt.swift` | 🟡 adapted |  |
| `hooks/src/events/mod.rs` | 10 | `hooks/src/events/events_mod.swift` | ✅ faithful |  |
| `hooks/src/events/permission_request.rs` | 337 | `hooks/src/events/permission_request.swift` | 🟡 adapted |  |
| `hooks/src/events/post_tool_use.rs` | 637 | `hooks/src/events/post_tool_use.swift` | 🟡 adapted |  |
| `hooks/src/events/pre_tool_use.rs` | 820 | `hooks/src/events/pre_tool_use.swift` | 🟡 adapted |  |
| `hooks/src/events/session_end.rs` | 139 | `hooks/src/events/session_end.swift` | 🟡 adapted |  |
| `hooks/src/events/session_start.rs` | 573 | `hooks/src/events/session_start.swift` | 🟡 adapted |  |
| `hooks/src/events/stop.rs` | 723 | `hooks/src/events/stop.swift` | 🟡 adapted |  |
| `hooks/src/events/user_prompt_submit.rs` | 492 | `hooks/src/events/user_prompt_submit.swift` | 🟡 adapted |  |
| `hooks/src/legacy_notify.rs` | 183 | `hooks/src/legacy_notify.swift` | 🟡 adapted |  |
| `hooks/src/lib.rs` | 123 | `hooks/src/lib.swift` | 🟡 adapted |  |
| `hooks/src/mcp.rs` | 24 | `hooks/src/mcp.swift` | ✅ faithful |  |
| `hooks/src/output_spill.rs` | 135 | `hooks/src/output_spill.swift` | 🟡 adapted |  |
| `hooks/src/registry.rs` | 336 | `hooks/src/registry.swift` | 🟡 adapted |  |
| `hooks/src/schema.rs` | 1,254 | `hooks/src/schema.swift` | 🟡 adapted |  |
| `hooks/src/types.rs` | 152 | `hooks/src/types.swift` | ✅ faithful |  |
| `skills/src/interface.rs` | 201 | `skills/src/interface.swift` | ✅ faithful |  |
| `skills/src/invocation.rs` | 160 | `skills/src/invocation.swift` | 🟡 adapted |  |
| `skills/src/lib.rs` | 214 | `skills/src/lib.swift` | 🟡 adapted |  |
| `skills/src/loading.rs` | 119 | `skills/src/loading.swift` | ✅ faithful |  |
| `skills/src/mentions.rs` | 232 | `skills/src/mentions.swift` | ✅ faithful |  |
| `skills/src/model.rs` | 112 | `skills/src/model.swift` | ✅ faithful |  |
| `skills/src/name_counts.rs` | 25 | `skills/src/name_counts.swift` | ✅ faithful |  |
| `skills/src/parser.rs` | 225 | `skills/src/parser.swift` | 🟡 adapted |  |
| `skills/src/selection.rs` | 205 | `skills/src/selection.swift` | ✅ faithful |  |

## Phase 9

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/agent/agent_resolver.rs` | 37 | `agent/agent_resolver.swift` | 🟡 adapted |  |
| `core/src/agent/api.rs` | 243 | `agent/agent_api.swift` | 🟡 adapted |  |
| `core/src/agent/child_config.rs` | 365 | `agent/child_config.swift` | 🟡 adapted |  |
| `core/src/agent/control/api.rs` | 289 | `agent/control/control_api.swift` | 🟡 adapted |  |
| `core/src/agent/control/budget.rs` | 39 | `agent/control/budget.swift` | ✅ faithful |  |
| `core/src/agent/control/completion.rs` | 131 | `agent/control/completion.swift` | 🟡 adapted |  |
| `core/src/agent/control/delivery.rs` | 43 | `agent/control/delivery.swift` | ✅ faithful |  |
| `core/src/agent/control/execution.rs` | 105 | `agent/control/execution.swift` | ✅ faithful |  |
| `core/src/agent/control/inspection.rs` | 30 | `agent/control/inspection.swift` | 🟡 adapted |  |
| `core/src/agent/control/interrupt.rs` | 52 | `agent/control/interrupt.swift` | 🟡 adapted |  |
| `core/src/agent/control/legacy.rs` | 124 | `agent/control/legacy.swift` | 🟡 adapted |  |
| `core/src/agent/control/residency.rs` | 276 | `agent/control/residency.swift` | 🟡 adapted |  |
| `core/src/agent/control/resume.rs` | 37 | `agent/control/resume.swift` | 🟡 adapted |  |
| `core/src/agent/control/runtime.rs` | 69 | `agent/control/runtime.swift` | 🟡 adapted |  |
| `core/src/agent/control/sender_context.rs` | 83 | `agent/control/sender_context.swift` | 🟡 adapted |  |
| `core/src/agent/control/service_tier.rs` | 21 | `agent/control/service_tier.swift` | ✅ faithful |  |
| `core/src/agent/control/spawn.rs` | 1,380 | `agent/control/control_spawn.swift` | 🟡 adapted |  |
| `core/src/agent/control/spawn_guard.rs` | 75 | `agent/control/spawn_guard.swift` | 🟡 adapted |  |
| `core/src/agent/control/target.rs` | 58 | `agent/control/target.swift` | 🟡 adapted |  |
| `core/src/agent/control/user_authorization.rs` | 284 | `agent/control/user_authorization.swift` | 🟡 adapted |  |
| `core/src/agent/control/watch.rs` | 61 | `agent/control/watch.swift` | 🟡 adapted |  |
| `core/src/agent/control.rs` | 904 | `agent/control.swift` | 🟡 adapted |  |
| `core/src/agent/mod.rs` | 14 | `agent/agent_mod.swift` | ✅ faithful |  |
| `core/src/agent/registry.rs` | 399 | `agent/registry.swift` | 🟡 adapted |  |
| `core/src/agent/role.rs` | 418 | `agent/role.swift` | 🟡 adapted |  |
| `core/src/agent/status.rs` | 31 | `agent/status.swift` | 🟡 adapted |  |
| `core/src/agent/types.rs` | 88 | `agent/types.swift` | 🟡 adapted |  |
| `core/src/agent_communication.rs` | 78 | `agent_communication.swift` | 🟡 adapted |  |
| `core/src/agent_message_board.rs` | 190 | `agent_message_board.swift` | 🟡 adapted |  |
| `core/src/apps/mod.rs` | 2 | `apps/apps_mod.swift` | ✅ faithful |  |
| `core/src/apps/render.rs` | 66 | `apps/apps_render.swift` | ✅ faithful |  |
| `core/src/connectors.rs` | 555 | `connectors.swift` | 🟡 adapted |  |
| `core/src/cyber_access_program.rs` | 12 | `cyber_access_program.swift` | 🟡 adapted |  |
| `core/src/environment_selection.rs` | 2,311 | `environment_selection.swift` | 🟡 adapted |  |
| `core/src/plugins/discoverable.rs` | 59 | `plugins/discoverable.swift` | 🟡 adapted |  |
| `core/src/plugins/injection.rs` | 59 | `plugins/injection.swift` | 🟡 adapted |  |
| `core/src/plugins/mentions.rs` | 121 | `plugins/mentions.swift` | ✅ faithful |  |
| `core/src/plugins/metrics.rs` | 62 | `plugins/metrics.swift` | 🟡 adapted |  |
| `core/src/plugins/mod.rs` | 46 | `plugins/plugins_mod.swift` | 🟡 adapted |  |
| `core/src/plugins/render.rs` | 92 | `plugins/plugins_render.swift` | ✅ faithful |  |
| `core/src/plugins/test_support.rs` | 109 | `plugins/test_support.swift` | 🟡 adapted |  |
| `core/src/session/multi_agents.rs` | 121 | `session_multi_agents.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/delegate.rs` | 497 | `tools/code_mode/delegate.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/execute_handler.rs` | 245 | `tools/code_mode/execute_handler.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/execute_spec.rs` | 104 | `tools/code_mode/execute_spec.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/mod.rs` | 567 | `tools/code_mode/code_mode_mod.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/output.rs` | 76 | `tools/code_mode/code_mode_output.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/response_adapter.rs` | 51 | `tools/code_mode/response_adapter.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/telemetry.rs` | 148 | `tools/code_mode/telemetry.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/wait_handler.rs` | 231 | `tools/code_mode/wait_handler.swift` | 🟡 adapted |  |
| `core/src/tools/code_mode/wait_spec.rs` | 126 | `tools/code_mode/wait_spec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/list_available_plugins_to_install.rs` | 181 | `tools/handlers/list_available_plugins_to_install.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/list_available_plugins_to_install_spec.rs` | 45 | `tools/handlers/list_available_plugins_to_install_spec.swift` | ✅ faithful |  |
| `core/src/tools/handlers/multi_agents/close_agent.rs` | 133 | `tools/handlers/multi_agents/close_agent.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents/resume_agent.rs` | 177 | `tools/handlers/multi_agents/resume_agent.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents/send_input.rs` | 173 | `tools/handlers/multi_agents/send_input.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents/spawn.rs` | 239 | - | 🟡 adapted | registry spawn; fork_context copies history; turn items on caller CodexThread |
| `core/src/tools/handlers/multi_agents/wait.rs` | 334 | - | 🟡 adapted | subscribeStatus wait; turn items on caller CodexThread |
| `core/src/tools/handlers/multi_agents.rs` | 99 | `tools/handlers/multi_agents.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_common.rs` | 157 | `tools/handlers/multi_agents_common.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_spec.rs` | 891 | `tools/handlers/multi_agents_spec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_v2/analytics.rs` | 62 | `tools/handlers/multi_agents_v2/analytics.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_v2/followup_task.rs` | 57 | `tools/handlers/multi_agents_v2/followup_task.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_v2/interrupt_agent.rs` | 104 | `tools/handlers/multi_agents_v2/interrupt_agent.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_v2/list_agents.rs` | 109 | `tools/handlers/multi_agents_v2/list_agents.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_v2/message_tool.rs` | 100 | `tools/handlers/multi_agents_v2/message_tool.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_v2/send_message.rs` | 57 | `tools/handlers/multi_agents_v2/send_message.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/multi_agents_v2/spawn.rs` | 330 | - | 🟡 adapted | registry spawn; fork_turns copies parent CodexThread history |
| `core/src/tools/handlers/multi_agents_v2/wait.rs` | 205 | - | 🟡 adapted | mailbox+steer wait; InputQueue races AgentDeliveryState; pending steer wins |
| `core/src/tools/handlers/multi_agents_v2.rs` | 66 | `tools/handlers/multi_agents_v2.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/request_plugin_install.rs` | 551 | `tools/handlers/request_plugin_install.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/request_plugin_install_spec.rs` | 189 | `tools/handlers/request_plugin_install_spec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/wait_for_environment.rs` | 182 | `tools/handlers/wait_for_environment.swift` | 🟡 adapted |  |

## Phase 10

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/context/realtime_delegation.rs` | 105 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/context/realtime_end_instructions.rs` | 51 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/context/realtime_start_instructions.rs` | 33 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/context/realtime_start_with_instructions.rs` | 42 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/lib.rs` | 247 | `lib.swift` | 🟡 adapted |  |
| `core/src/otel_init.rs` | 111 | `otel_init.swift` | 🟡 adapted |  |
| `core/src/realtime_context.rs` | 583 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation/bem.rs` | 71 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation/existing_call.rs` | 90 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation/sideband.rs` | 195 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation.rs` | 2,709 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_history/presentation.rs` | 129 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_history.rs` | 450 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_prompt.rs` | 82 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/session/realtime_history.rs` | 56 | - | 💤 deferred | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/test_support.rs` | 264 | `core_test_support.swift` | 🟡 adapted |  |
| `otel/src/config.rs` | 120 | `otel/src/config.swift` | 🟡 adapted |  |
| `otel/src/events/mod.rs` | 2 | `otel/src/events/mod.swift` | ✅ faithful |  |
| `otel/src/events/session_telemetry.rs` | 1,358 | `otel/src/events/session_telemetry.swift` | 🟡 adapted |  |
| `otel/src/events/shared.rs` | 70 | `otel/src/events/shared.swift` | 🟡 adapted |  |
| `otel/src/lib.rs` | 94 | `otel/src/lib.swift` | 🟡 adapted |  |
| `otel/src/metrics/client.rs` | 677 | `otel/src/metrics/client.swift` | 🟡 adapted |  |
| `otel/src/metrics/config.rs` | 135 | `otel/src/metrics/metrics_config.swift` | 🟡 adapted |  |
| `otel/src/metrics/error.rs` | 46 | `otel/src/metrics/error.swift` | 🟡 adapted |  |
| `otel/src/metrics/mod.rs` | 58 | `otel/src/metrics/metrics_mod.swift` | 🟡 adapted |  |
| `otel/src/metrics/names.rs` | 70 | `otel/src/metrics/names.swift` | ✅ faithful |  |
| `otel/src/metrics/process.rs` | 27 | `otel/src/metrics/process.swift` | ✅ faithful |  |
| `otel/src/metrics/runtime_metrics.rs` | 220 | `otel/src/metrics/runtime_metrics.swift` | 🟡 adapted |  |
| `otel/src/metrics/tags.rs` | 134 | `otel/src/metrics/tags.swift` | ✅ faithful |  |
| `otel/src/metrics/timer.rs` | 41 | `otel/src/metrics/timer.swift` | 🟡 adapted |  |
| `otel/src/metrics/validation.rs` | 55 | `otel/src/metrics/validation.swift` | ✅ faithful |  |
| `otel/src/network_policy.rs` | 127 | `otel/src/network_policy.swift` | 🟡 adapted |  |
| `otel/src/otlp.rs` | 277 | `otel/src/otlp.swift` | 🟡 adapted |  |
| `otel/src/provider.rs` | 851 | `otel/src/provider.swift` | 🟡 adapted |  |
| `otel/src/targets.rs` | 11 | `otel/src/targets.swift` | ✅ faithful |  |
| `otel/src/tool_result.rs` | 114 | `otel/src/tool_result.swift` | 🟡 adapted |  |
| `otel/src/trace_context.rs` | 411 | `otel/src/trace_context.swift` | 🟡 adapted |  |
| `terminal-detection/src/lib.rs` | 423 | `terminal-detection/src/lib.swift` | ✅ faithful |  |

## 不计入范围（平台/测试）

| codex 文件 | 备注 |
|---|---|
| `core/src/context/world_state/test_support.rs` | test-only |
| `core/src/guardian/test_host.rs` | test-only |
| `core/src/windows_sandbox.rs` | platform: Windows 沙盒 |
| `core/src/windows_sandbox_read_grants.rs` | platform: Windows 沙盒 |
| `core/src/windows_system_config.rs` | platform: Windows 沙盒 |

## Sage 新增（无 codex 对应）

| Swift 文件 | 备注 |
|---|---|
| `Tests/Phase10OtelTests/Phase10OtelTests.swift` | Sage 新增，无 codex 对应 |
| `Tests/Phase7PersistenceTests/Phase7PersistenceTests.swift` | Sage 新增，无 codex 对应 |
| `Tests/Phase8GuardianSkillsTests/Phase8GuardianSkillsTests.swift` | Sage 新增，无 codex 对应 |
| `Tests/Phase9AgentTests/Phase9AgentTests.swift` | Sage 新增，无 codex 对应 |
| `async-utils/src/cancellation_token.swift` | Sage 新增，无 codex 对应 |
| `context/context_fragments_bridge.swift` | Sage 新增，无 codex 对应 |
| `protocol/src/json_value.swift` | Sage 新增，无 codex 对应 |
| `protocol/src/serde_helpers.swift` | Sage 新增，无 codex 对应 |
| `protocol/src/uuid_v7.swift` | Sage 新增，无 codex 对应 |
| `tasks/explore.swift` | Sage 新增，无 codex 对应 |
| `tasks/execute_attach.swift` | Sage 新增：AgentEvent → Session / TurnContext 挂载；Responses client 租约 |
| `tools/handlers/sage_execute.swift` | Sage 新增：execute 工具 → onSageToolCall |
| `utils/io_error.swift` | Sage 新增，无 codex 对应 |
| `utils/path-uri/src/file_url.swift` | Sage 新增，无 codex 对应 |
| `utils/path-uri/src/url_encoding.swift` | Sage 新增，无 codex 对应 |
| `utils/pty/src/child_reaper.swift` | Sage 新增，无 codex 对应 |
