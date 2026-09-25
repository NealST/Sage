# Execute Harness 移植追踪表

> 由 `scripts/harness_port.py generate` 生成（9ef08dcf 基线）。
> 状态随 PR 手工更新；`check` 模式校验文件头与本表一致。
> 重新生成会保留未移植行的手工状态与备注；已移植行以 Swift 文件头为准。

状态图例：✅ faithful ｜ 🟡 adapted / partial ｜ 🟥 stub ｜ ⬜ 未开始 ｜ ⛔ excluded(platform/test) ｜ 💤 deferred

## 进度汇总

| Phase | 文件数 | ✅ | 🟡 | 🟥 | ⬜ | ⛔/💤 |
|---|---:|---:|---:|---:|---:|---:|
| Phase 1 | 96 | 65 | 26 | 0 | 1 | 0 |
| Phase 2 | 26 | 10 | 15 | 0 | 0 | 0 |
| Phase 3 | 86 | 15 | 29 | 0 | 31 | 7 |
| Phase 4 | 114 | 0 | 8 | 0 | 65 | 0 |
| Phase 5 | 156 | 0 | 4 | 0 | 152 | 0 |
| Phase 6 | 51 | 0 | 0 | 0 | 38 | 0 |
| Phase 7 | 126 | 0 | 0 | 0 | 126 | 0 |
| Phase 8 | 71 | 2 | 13 | 0 | 56 | 0 |
| Phase 9 | 75 | 0 | 0 | 0 | 75 | 0 |
| Phase 10 | 43 | 0 | 0 | 0 | 43 | 0 |

## Phase 1

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/util.rs` | 101 | `util.swift` | 🟡 adapted |  |
| `core/src/utils/json.rs` | 22 | `utils/json.swift` | 🟡 adapted |  |
| `core/src/utils/mod.rs` | 2 | `utils/mod.swift` | ✅ faithful |  |
| `core/src/utils/path_utils.rs` | 1 | `utils/path_utils.swift` | ✅ faithful |  |
| `async-utils/src/backoff.rs` | 17 | `async-utils/src/backoff.swift` | ✅ faithful |  |
| `async-utils/src/lib.rs` | 93 | `async-utils/src/lib.swift` | 🟡 adapted |  |
| `protocol/src/account.rs` | 261 | `protocol/src/account.swift` | ✅ faithful |  |
| `protocol/src/agent_path.rs` | 240 | `protocol/src/agent_path.swift` | ✅ faithful |  |
| `protocol/src/approvals.rs` | 548 | `protocol/src/approvals.swift` | ✅ faithful |  |
| `protocol/src/auth.rs` | 254 | `protocol/src/auth.swift` | ✅ faithful |  |
| `protocol/src/capabilities.rs` | 51 | `protocol/src/capabilities.swift` | ✅ faithful |  |
| `protocol/src/codex_error_info.rs` | 84 | `protocol/src/codex_error_info.swift` | ✅ faithful |  |
| `protocol/src/config_types.rs` | 980 | `protocol/src/config_types.swift` | ✅ faithful |  |
| `protocol/src/dynamic_tools.rs` | 175 | `protocol/src/dynamic_tools.swift` | ✅ faithful |  |
| `protocol/src/environment.rs` | 101 | `protocol/src/environment.swift` | 🟡 adapted |  |
| `protocol/src/error.rs` | 907 | `protocol/src/error.swift` | 🟡 adapted |  |
| `protocol/src/exec_output.rs` | 169 | `protocol/src/exec_output.swift` | 🟡 adapted |  |
| `protocol/src/items.rs` | 874 | `protocol/src/items.swift` | 🟡 adapted |  |
| `protocol/src/legacy_events.rs` | 685 | `protocol/src/legacy_events.swift` | ✅ faithful |  |
| `protocol/src/lib.rs` | 56 | `protocol/src/lib.swift` | ✅ faithful |  |
| `protocol/src/local_media.rs` | 96 | `protocol/src/local_media.swift` | ✅ faithful |  |
| `protocol/src/mcp.rs` | 634 | `protocol/src/mcp.swift` | ✅ faithful |  |
| `protocol/src/mcp_approval_meta.rs` | 29 | `protocol/src/mcp_approval_meta.swift` | ✅ faithful |  |
| `protocol/src/mcp_policy.rs` | 96 | `protocol/src/mcp_policy.swift` | ✅ faithful |  |
| `protocol/src/memory_citation.rs` | 20 | `protocol/src/memory_citation.swift` | ✅ faithful |  |
| `protocol/src/memory_version.rs` | 23 | `protocol/src/memory_version.swift` | ✅ faithful |  |
| `protocol/src/models/configuration_update.rs` | 17 | `protocol/src/models/configuration_update.swift` | ✅ faithful |  |
| `protocol/src/models/executed_tool_calls.rs` | 956 | `protocol/src/models/executed_tool_calls.swift` | ✅ faithful |  |
| `protocol/src/models/item_metadata.rs` | 11 | `protocol/src/models/item_metadata.swift` | ✅ faithful |  |
| `protocol/src/models.rs` | 4,566 | `protocol/src/models.swift` | 🟡 partial |  |
| `protocol/src/network_policy.rs` | 22 | `protocol/src/network_policy.swift` | 🟡 adapted |  |
| `protocol/src/num_format.rs` | 29 | `protocol/src/num_format.swift` | ✅ faithful |  |
| `protocol/src/openai_models/access_programs.rs` | 31 | - | ✅ faithful | included in openai_models.swift |
| `protocol/src/openai_models/guardian.rs` | 184 | - | ✅ faithful | included in openai_models.swift |
| `protocol/src/openai_models/guardian_v2.rs` | 48 | - | ✅ faithful | included in openai_models.swift |
| `protocol/src/openai_models/reasoning_effort.rs` | 44 | - | ✅ faithful | included in openai_models.swift |
| `protocol/src/openai_models.rs` | 2,011 | `protocol/src/openai_models.swift` | ✅ faithful |  |
| `protocol/src/parse_command.rs` | 31 | `protocol/src/parse_command.swift` | ✅ faithful |  |
| `protocol/src/permission_profile_intersection.rs` | 425 | `protocol/src/permission_profile_intersection.swift` | ✅ faithful |  |
| `protocol/src/permission_profile_snapshot.rs` | 128 | `protocol/src/permission_profile_snapshot.swift` | ✅ faithful |  |
| `protocol/src/permissions/deny_read_validator.rs` | 102 | `protocol/src/permissions/deny_read_validator.swift` | ✅ faithful |  |
| `protocol/src/permissions/local_aliases.rs` | 131 | `protocol/src/permissions/local_aliases.swift` | 🟡 adapted |  |
| `protocol/src/permissions/target.rs` | 195 | `protocol/src/permissions/target.swift` | ✅ faithful |  |
| `protocol/src/permissions/windows_glob.rs` | 44 | `protocol/src/permissions/windows_glob.swift` | ✅ faithful |  |
| `protocol/src/permissions.rs` | 4,591 | `protocol/src/permissions.swift` | 🟡 adapted |  |
| `protocol/src/plan_tool.rs` | 29 | `protocol/src/plan_tool.swift` | ✅ faithful |  |
| `protocol/src/protocol.rs` | 6,451 | `protocol/src/protocol.swift` | 🟡 partial |  |
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
| `utils/absolute-path/src/lib.rs` | 781 | `utils/absolute-path/src/lib.swift` | ✅ faithful |  |
| `utils/absolute-path/src/system_aliases.rs` | 35 | - | ⬜ 未开始 |  |
| `utils/audio/src/lib.rs` | 267 | `utils/audio/src/audio_lib.swift` | 🟡 adapted |  |
| `utils/cache/src/lib.rs` | 218 | `utils/cache/src/cache_lib.swift` | 🟡 adapted |  |
| `utils/git-discovery/src/lib.rs` | 120 | `utils/git-discovery/src/git_discovery_lib.swift` | 🟡 adapted |  |
| `utils/home-dir/src/lib.rs` | 134 | `utils/home-dir/src/home_dir_lib.swift` | ✅ faithful |  |
| `utils/image/src/error.rs` | 63 | `utils/image/src/error.swift` | 🟡 adapted |  |
| `utils/image/src/lib.rs` | 462 | `utils/image/src/image_lib.swift` | 🟡 adapted |  |
| `utils/output-truncation/src/lib.rs` | 215 | `utils/output-truncation/src/output_truncation_lib.swift` | 🟡 partial |  |
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
| `git-utils/src/lib.rs` | 58 | `git-utils/src/lib.swift` | ✅ faithful |  |
| `git-utils/src/operations.rs` | 172 | `git-utils/src/operations.swift` | 🟡 adapted |  |
| `git-utils/src/platform.rs` | 37 | `git-utils/src/platform.swift` | 🟡 adapted |  |
| `git-utils/src/status.rs` | 83 | `git-utils/src/status.swift` | 🟡 adapted |  |
| `git-utils/src/trust.rs` | 250 | `git-utils/src/trust.swift` | 🟡 adapted |  |
| `git-utils/src/worktree.rs` | 178 | `git-utils/src/worktree.swift` | 🟡 adapted |  |

## Phase 3

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/apply_patch.rs` | 94 | - | ⬜ 未开始 |  |
| `core/src/command_canonicalization.rs` | 42 | `command_canonicalization.swift` | ✅ faithful |  |
| `core/src/exec.rs` | 1,276 | - | ⬜ 未开始 |  |
| `core/src/exec_env.rs` | 117 | `exec_env.swift` | 🟡 adapted |  |
| `core/src/exec_policy/executable_identity.rs` | 107 | - | ⬜ 未开始 |  |
| `core/src/exec_policy/model_policy.rs` | 60 | - | ⬜ 未开始 |  |
| `core/src/exec_policy.rs` | 1,175 | - | ⬜ 未开始 |  |
| `core/src/safety.rs` | 184 | `safety.swift` | ✅ faithful |  |
| `core/src/sandbox_tags.rs` | 114 | `sandbox_tags.swift` | 🟡 adapted |  |
| `core/src/sandboxing/mod.rs` | 218 | - | ⬜ 未开始 |  |
| `core/src/shell.rs` | 104 | `shell.swift` | 🟡 adapted |  |
| `core/src/shell_snapshot.rs` | 1,188 | - | ⬜ 未开始 |  |
| `core/src/shell_snapshot_sandbox.rs` | 224 | - | ⬜ 未开始 |  |
| `core/src/spawn.rs` | 137 | `spawn.swift` | 🟡 adapted |  |
| `core/src/unified_exec/async_watcher.rs` | 473 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/errors.rs` | 71 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/head_tail_buffer.rs` | 169 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/mod.rs` | 249 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/oneshot.rs` | 123 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/process.rs` | 667 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/process_manager.rs` | 1,898 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/process_state.rs` | 27 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/shell_snapshot.rs` | 202 | - | ⬜ 未开始 |  |
| `core/src/unified_exec/stdin_approval.rs` | 249 | - | ⬜ 未开始 |  |
| `core/src/user_shell_command.rs` | 44 | `user_shell_command.swift` | 🟡 partial |  |
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
| `sandboxing/src/manager.rs` | 802 | `sandboxing/src/manager.swift` | 🟡 partial |  |
| `sandboxing/src/policy_transforms.rs` | 670 | `sandboxing/src/policy_transforms.swift` | 🟡 partial |  |
| `sandboxing/src/seatbelt.rs` | 1,115 | `sandboxing/src/seatbelt.swift` | 🟡 partial |  |
| `sandboxing/src/seatbelt_daemon.rs` | 24 | `sandboxing/src/seatbelt_daemon.swift` | ✅ faithful |  |
| `sandboxing/src/seatbelt_scratch.rs` | 69 | `sandboxing/src/seatbelt_scratch.swift` | ✅ faithful |  |
| `sandboxing/src/spawn.rs` | 142 | `sandboxing/src/spawn.swift` | 🟡 adapted |  |
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
| `shell-command/src/parse_command.rs` | 2,766 | `shell-command/src/parse_command.swift` | 🟡 partial |  |
| `shell-command/src/powershell.rs` | 291 | `shell-command/src/powershell.swift` | 🟡 adapted | 适配项：macOS 仅需 bash/zsh/sh，保留同名文件标注 |
| `shell-command/src/shell_detect.rs` | 495 | `shell-command/src/shell_detect.swift` | 🟡 adapted |  |
| `shell-command/src/shell_snapshot.rs` | 112 | `shell-command/src/shell_snapshot.swift` | 🟡 partial |  |
| `shell-command/src/shell_snapshot_capture.rs` | 408 | `shell-command/src/shell_snapshot_capture.swift` | 🟡 partial |  |
| `shell-command/src/shell_snapshot_credentials.rs` | 342 | `shell-command/src/shell_snapshot_credentials.swift` | 🟡 partial |  |
| `shell-command/src/shell_snapshot_exports.rs` | 81 | `shell-command/src/shell_snapshot_exports.swift` | 🟡 partial |  |
| `shell-command/src/shell_snapshot_literals.rs` | 715 | `shell-command/src/shell_snapshot_literals.swift` | 🟡 partial |  |
| `shell-command/src/shell_snapshot_render.rs` | 106 | `shell-command/src/shell_snapshot_render.swift` | 🟡 partial |  |
| `shell-command/src/startup.rs` | 30 | `shell-command/src/startup.swift` | ✅ faithful |  |
| `utils/pty/src/child.rs` | 139 | - | ⬜ 未开始 |  |
| `utils/pty/src/child_command.rs` | 370 | - | ⬜ 未开始 |  |
| `utils/pty/src/child_reaper.rs` | 68 | - | ⬜ 未开始 |  |
| `utils/pty/src/lib.rs` | 70 | - | ⬜ 未开始 |  |
| `utils/pty/src/linux_fds.rs` | 129 | - | ⬜ 未开始 |  |
| `utils/pty/src/pipe.rs` | 370 | - | ⬜ 未开始 |  |
| `utils/pty/src/posix_child.rs` | 480 | - | ⬜ 未开始 |  |
| `utils/pty/src/process.rs` | 481 | - | ⬜ 未开始 |  |
| `utils/pty/src/process_group.rs` | 309 | - | ⬜ 未开始 |  |
| `utils/pty/src/pty.rs` | 679 | - | ⬜ 未开始 |  |
| `utils/pty/src/spawn_helper.rs` | 201 | - | ⬜ 未开始 |  |
| `utils/pty/src/spawn_helper_main.rs` | 119 | - | ⬜ 未开始 |  |
| `utils/pty/src/unix_io.rs` | 109 | - | ⬜ 未开始 |  |
| `utils/pty/src/win/conpty.rs` | 192 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/job.rs` | 232 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/mod.rs` | 181 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/procthreadattr.rs` | 127 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/win/psuedocon.rs` | 387 | - | ⛔ excluded | platform: Windows PTY |
| `utils/pty/src/windows_input.rs` | 35 | - | ⛔ excluded | platform: Windows PTY |

## Phase 4

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/function_tool.rs` | 1 | - | ⬜ 未开始 |  |
| `core/src/network_policy_decision.rs` | 106 | - | ⬜ 未开始 |  |
| `core/src/tools/approvals.rs` | 889 | `tools/approvals.swift` | 🟡 partial |  |
| `core/src/tools/call_trace.rs` | 88 | - | ⬜ 未开始 |  |
| `core/src/tools/catalog_parameters.rs` | 14 | - | ⬜ 未开始 |  |
| `core/src/tools/context.rs` | 607 | - | ⬜ 未开始 |  |
| `core/src/tools/control_tool_analytics.rs` | 58 | - | ⬜ 未开始 |  |
| `core/src/tools/events.rs` | 889 | - | ⬜ 未开始 |  |
| `core/src/tools/executed_tool_calls/mcp_attribution.rs` | 180 | - | ⬜ 未开始 |  |
| `core/src/tools/executed_tool_calls/request_metadata.rs` | 456 | - | ⬜ 未开始 |  |
| `core/src/tools/executed_tool_calls/seen_ids.rs` | 133 | - | ⬜ 未开始 |  |
| `core/src/tools/executed_tool_calls.rs` | 696 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/apply_patch.rs` | 626 | `tools/handlers/apply_patch.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/apply_patch_spec.rs` | 32 | `tools/handlers/apply_patch_spec.swift` | 🟡 adapted |  |
| `core/src/tools/handlers/current_time.rs` | 130 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/dynamic.rs` | 251 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/extension_tools.rs` | 640 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/get_context_remaining.rs` | 94 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/get_context_remaining_spec.rs` | 36 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/mcp.rs` | 902 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/mcp_resource/list_mcp_resource_templates.rs` | 111 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/mcp_resource/list_mcp_resources.rs` | 109 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/mcp_resource/read_mcp_resource.rs` | 108 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/mcp_resource.rs` | 414 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/mcp_resource_spec.rs` | 120 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/mod.rs` | 617 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/new_context_window.rs` | 48 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/new_context_window_spec.rs` | 17 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/plan.rs` | 112 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/plan_spec.rs` | 58 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/request_permissions.rs` | 209 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/request_user_input.rs` | 163 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/request_user_input_async.rs` | 156 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/request_user_input_spec.rs` | 146 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/send_message_to_user_async.rs` | 109 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/shell_spec.rs` | 348 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/sleep.rs` | 167 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/test_sync.rs` | 196 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/test_sync_spec.rs` | 70 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/tool_search.rs` | 500 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/tool_search_spec.rs` | 221 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/unified_exec/exec_command.rs` | 569 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/unified_exec/write_stdin.rs` | 145 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/unified_exec.rs` | 159 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/view_image.rs` | 526 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/view_image_spec.rs` | 74 | - | ⬜ 未开始 |  |
| `core/src/tools/hook_names.rs` | 67 | - | ⬜ 未开始 |  |
| `core/src/tools/hosted_spec.rs` | 50 | - | ⬜ 未开始 |  |
| `core/src/tools/lifecycle.rs` | 177 | - | ⬜ 未开始 |  |
| `core/src/tools/metadata_metrics.rs` | 61 | - | ⬜ 未开始 |  |
| `core/src/tools/mod.rs` | 148 | - | ⬜ 未开始 |  |
| `core/src/tools/multi_agent_tool.rs` | 133 | - | ⬜ 未开始 |  |
| `core/src/tools/network_approval.rs` | 1,254 | `tools/network_approval.swift` | 🟡 adapted |  |
| `core/src/tools/orchestrator.rs` | 551 | `tools/orchestrator.swift` | 🟡 adapted |  |
| `core/src/tools/parallel.rs` | 813 | `tools/parallel.swift` | 🟡 adapted |  |
| `core/src/tools/registry.rs` | 865 | - | ⬜ 未开始 |  |
| `core/src/tools/router.rs` | 389 | - | ⬜ 未开始 |  |
| `core/src/tools/runtimes/apply_patch.rs` | 242 | `tools/runtimes/apply_patch.swift` | 🟡 partial |  |
| `core/src/tools/runtimes/mod.rs` | 918 | - | ⬜ 未开始 |  |
| `core/src/tools/runtimes/unified_exec/launch.rs` | 75 | - | ⬜ 未开始 |  |
| `core/src/tools/runtimes/unified_exec.rs` | 981 | - | ⬜ 未开始 |  |
| `core/src/tools/runtimes/zsh_fork/unix_escalation.rs` | 875 | - | ⬜ 未开始 |  |
| `core/src/tools/runtimes/zsh_fork.rs` | 105 | - | ⬜ 未开始 |  |
| `core/src/tools/sandboxing.rs` | 561 | `tools/sandboxing.swift` | 🟡 adapted |  |
| `core/src/tools/spec_plan.rs` | 1,534 | - | ⬜ 未开始 |  |
| `core/src/tools/tool_dispatch_trace.rs` | 128 | - | ⬜ 未开始 |  |
| `core/src/tools/tool_namespaces_info.rs` | 111 | - | ⬜ 未开始 |  |
| `core/src/tools/user_messaging.rs` | 35 | - | ⬜ 未开始 |  |
| `network-proxy/src/attribution.rs` | 145 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/authorization_path.rs` | 64 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/brokered_tunnel.rs` | 217 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/certs.rs` | 1,283 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/config.rs` | 1,233 | - | ⬜ 未开始 | 策略类型层 |
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
| `network-proxy/src/environment_policy.rs` | 97 | - | ⬜ 未开始 | 策略类型层 |
| `network-proxy/src/http_proxy.rs` | 1,917 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/lib.rs` | 125 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/main.rs` | 119 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/mitm.rs` | 639 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/mitm_hook.rs` | 1,086 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/native_certs.rs` | 260 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/network_policy.rs` | 1,124 | - | ⬜ 未开始 | 策略类型层 |
| `network-proxy/src/policy.rs` | 559 | - | ⬜ 未开始 | 策略类型层 |
| `network-proxy/src/process_log_metadata.rs` | 17 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/proxy/execution_scope.rs` | 53 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/proxy.rs` | 3,087 | - | ⛔ excluded | 适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记） |
| `network-proxy/src/reasons.rs` | 9 | - | ⬜ 未开始 | 策略类型层 |
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
| `core/src/compact.rs` | 840 | - | ⬜ 未开始 |  |
| `core/src/compact_model_fallback.rs` | 59 | - | ⬜ 未开始 |  |
| `core/src/compact_remote_history.rs` | 190 | - | ⬜ 未开始 |  |
| `core/src/compact_remote_v2.rs` | 1,272 | - | ⬜ 未开始 |  |
| `core/src/compact_remote_v2_attempt.rs` | 133 | - | ⬜ 未开始 |  |
| `core/src/compact_remote_v2_images.rs` | 100 | - | ⬜ 未开始 |  |
| `core/src/compact_token_budget.rs` | 84 | - | ⬜ 未开始 |  |
| `core/src/config/auth_keyring.rs` | 122 | - | ⬜ 未开始 |  |
| `core/src/config/edit/bedrock.rs` | 37 | - | ⬜ 未开始 |  |
| `core/src/config/edit/document_helpers.rs` | 354 | - | ⬜ 未开始 |  |
| `core/src/config/edit.rs` | 989 | - | ⬜ 未开始 |  |
| `core/src/config/managed_features.rs` | 349 | - | ⬜ 未开始 |  |
| `core/src/config/metrics.rs` | 26 | - | ⬜ 未开始 |  |
| `core/src/config/mod.rs` | 4,922 | - | ⬜ 未开始 |  |
| `core/src/config/network_config.rs` | 176 | - | ⬜ 未开始 |  |
| `core/src/config/network_proxy_spec.rs` | 546 | `config/network_proxy_spec.swift` | 🟡 adapted |  |
| `core/src/config/otel.rs` | 120 | - | ⬜ 未开始 |  |
| `core/src/config/permission_path.rs` | 75 | - | ⬜ 未开始 |  |
| `core/src/config/permission_profile_catalog.rs` | 137 | - | ⬜ 未开始 |  |
| `core/src/config/permission_profile_selection.rs` | 39 | - | ⬜ 未开始 |  |
| `core/src/config/permissions.rs` | 893 | - | ⬜ 未开始 |  |
| `core/src/config/requirements.rs` | 178 | - | ⬜ 未开始 |  |
| `core/src/config/resolved_permission_profile.rs` | 93 | - | ⬜ 未开始 |  |
| `core/src/config/schema.rs` | 7 | - | ⬜ 未开始 |  |
| `core/src/config/token_budget_startup.rs` | 31 | - | ⬜ 未开始 |  |
| `core/src/config/windows_sandbox_config.rs` | 126 | - | ⬜ 未开始 |  |
| `core/src/context/agent_message_board_notification.rs` | 42 | - | ⬜ 未开始 |  |
| `core/src/context/approved_command_prefix_saved.rs` | 43 | - | ⬜ 未开始 |  |
| `core/src/context/apps_instructions.rs` | 33 | - | ⬜ 未开始 |  |
| `core/src/context/available_plugins_instructions.rs` | 49 | - | ⬜ 未开始 |  |
| `core/src/context/base_instructions.rs` | 31 | - | ⬜ 未开始 |  |
| `core/src/context/compaction_summary.rs` | 37 | - | ⬜ 未开始 |  |
| `core/src/context/contextual_user_message.rs` | 121 | - | ⬜ 未开始 |  |
| `core/src/context/current_time_reminder.rs` | 71 | - | ⬜ 未开始 |  |
| `core/src/context/developer_instructions.rs` | 37 | - | ⬜ 未开始 |  |
| `core/src/context/environment_context.rs` | 243 | - | ⬜ 未开始 |  |
| `core/src/context/environments_instructions.rs` | 38 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_approved_action.rs` | 48 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_budget_omission.rs` | 32 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_context_mode.rs` | 37 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_followup_review_reminder.rs` | 34 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_node_repl_policy.rs` | 39 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_policy.rs` | 42 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_review_evidence.rs` | 211 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_sender_messages.rs` | 58 | - | ⬜ 未开始 |  |
| `core/src/context/guardian_tool_descriptions.rs` | 58 | - | ⬜ 未开始 |  |
| `core/src/context/hook_additional_context.rs` | 35 | - | ⬜ 未开始 |  |
| `core/src/context/image_resize_notice.rs` | 79 | - | ⬜ 未开始 |  |
| `core/src/context/inter_agent_completion_message.rs` | 46 | - | ⬜ 未开始 |  |
| `core/src/context/inter_agent_message.rs` | 71 | - | ⬜ 未开始 |  |
| `core/src/context/internal_model_context.rs` | 134 | - | ⬜ 未开始 |  |
| `core/src/context/legacy_apply_patch_exec_command_warning.rs` | 34 | - | ⬜ 未开始 |  |
| `core/src/context/legacy_model_mismatch_warning.rs` | 34 | - | ⬜ 未开始 |  |
| `core/src/context/legacy_unified_exec_process_limit_warning.rs` | 34 | - | ⬜ 未开始 |  |
| `core/src/context/memory.rs` | 43 | - | ⬜ 未开始 |  |
| `core/src/context/mod.rs` | 129 | - | ⬜ 未开始 |  |
| `core/src/context/model_switch_instructions.rs` | 44 | - | ⬜ 未开始 |  |
| `core/src/context/multi_agent_mode_instructions.rs` | 54 | - | ⬜ 未开始 |  |
| `core/src/context/multi_agent_usage_hint.rs` | 42 | - | ⬜ 未开始 |  |
| `core/src/context/network_rule_saved.rs` | 48 | - | ⬜ 未开始 |  |
| `core/src/context/node_repl_review_evidence.rs` | 316 | - | ⬜ 未开始 |  |
| `core/src/context/plugin_instructions.rs` | 35 | - | ⬜ 未开始 |  |
| `core/src/context/recommended_plugins_instructions.rs` | 55 | - | ⬜ 未开始 |  |
| `core/src/context/rollout_budget.rs` | 32 | - | ⬜ 未开始 |  |
| `core/src/context/subagent_notification.rs` | 47 | - | ⬜ 未开始 |  |
| `core/src/context/token_budget_context.rs` | 245 | - | ⬜ 未开始 |  |
| `core/src/context/turn_aborted.rs` | 40 | - | ⬜ 未开始 |  |
| `core/src/context/unsupported_media.rs` | 42 | - | ⬜ 未开始 |  |
| `core/src/context/user_goal.rs` | 105 | - | ⬜ 未开始 |  |
| `core/src/context/user_instructions.rs` | 35 | - | ⬜ 未开始 |  |
| `core/src/context/user_shell_command.rs` | 53 | - | ⬜ 未开始 |  |
| `core/src/context/user_verification_notice.rs` | 28 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/agents_md.rs` | 84 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/apps_instructions.rs` | 55 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/collaboration_mode.rs` | 177 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/compact_permissions.rs` | 59 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/context_window_guidance.rs` | 76 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/environment.rs` | 557 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/environments_instructions.rs` | 55 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/managed_developer_instructions.rs` | 157 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/mod.rs` | 556 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/model.rs` | 65 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/multi_agent_mode.rs` | 91 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/multi_agent_usage_hint.rs` | 50 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/permissions.rs` | 135 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/persistent_mode.rs` | 120 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/plugins_instructions.rs` | 55 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/realtime.rs` | 96 | - | ⬜ 未开始 |  |
| `core/src/context/world_state/tools.rs` | 233 | - | ⬜ 未开始 |  |
| `core/src/context_manager/history.rs` | 1,256 | - | ⬜ 未开始 |  |
| `core/src/context_manager/history_user_authorization.rs` | 204 | - | ⬜ 未开始 |  |
| `core/src/context_manager/mod.rs` | 9 | - | ⬜ 未开始 |  |
| `core/src/context_manager/normalize.rs` | 420 | - | ⬜ 未开始 |  |
| `core/src/context_manager/updates.rs` | 60 | - | ⬜ 未开始 |  |
| `core/src/event_mapping.rs` | 261 | - | ⬜ 未开始 |  |
| `core/src/mcp.rs` | 421 | - | ⬜ 未开始 |  |
| `core/src/mcp_openai_file.rs` | 698 | - | ⬜ 未开始 |  |
| `core/src/mcp_skill_dependencies.rs` | 535 | - | ⬜ 未开始 |  |
| `core/src/mcp_tool_approval_templates.rs` | 371 | - | ⬜ 未开始 |  |
| `core/src/mcp_tool_call/account.rs` | 39 | - | ⬜ 未开始 |  |
| `core/src/mcp_tool_call/telemetry.rs` | 166 | - | ⬜ 未开始 |  |
| `core/src/mcp_tool_call.rs` | 2,510 | - | ⬜ 未开始 |  |
| `core/src/mcp_tool_exposure.rs` | 192 | - | ⬜ 未开始 |  |
| `core/src/session/code_mode_warning.rs` | 26 | - | ⬜ 未开始 |  |
| `core/src/session/context_window.rs` | 130 | - | ⬜ 未开始 |  |
| `core/src/session/daemon_recovery.rs` | 46 | - | ⬜ 未开始 |  |
| `core/src/session/environment.rs` | 307 | - | ⬜ 未开始 |  |
| `core/src/session/extension_interruption.rs` | 117 | - | ⬜ 未开始 |  |
| `core/src/session/extension_metrics.rs` | 35 | - | ⬜ 未开始 |  |
| `core/src/session/guardian_checkpoint.rs` | 47 | - | ⬜ 未开始 |  |
| `core/src/session/handlers.rs` | 716 | - | ⬜ 未开始 |  |
| `core/src/session/inject.rs` | 193 | - | ⬜ 未开始 |  |
| `core/src/session/input_queue.rs` | 681 | - | ⬜ 未开始 |  |
| `core/src/session/mcp.rs` | 1,219 | - | ⬜ 未开始 |  |
| `core/src/session/mcp_prewarm.rs` | 82 | - | ⬜ 未开始 |  |
| `core/src/session/mcp_refresh.rs` | 56 | - | ⬜ 未开始 |  |
| `core/src/session/mcp_runtime.rs` | 380 | - | ⬜ 未开始 |  |
| `core/src/session/mod.rs` | 5,161 | - | ⬜ 未开始 |  |
| `core/src/session/plugin_selection.rs` | 32 | - | ⬜ 未开始 |  |
| `core/src/session/reasoning_effort.rs` | 162 | - | ⬜ 未开始 |  |
| `core/src/session/retained_context.rs` | 86 | - | ⬜ 未开始 |  |
| `core/src/session/review.rs` | 229 | - | ⬜ 未开始 |  |
| `core/src/session/rollout_budget.rs` | 40 | - | ⬜ 未开始 |  |
| `core/src/session/rollout_reconstruction.rs` | 563 | - | ⬜ 未开始 |  |
| `core/src/session/session.rs` | 1,928 | - | ⬜ 未开始 |  |
| `core/src/session/startup.rs` | 37 | - | ⬜ 未开始 |  |
| `core/src/session/startup_prewarm.rs` | 413 | - | ⬜ 未开始 |  |
| `core/src/session/step_activation.rs` | 472 | - | ⬜ 未开始 |  |
| `core/src/session/step_context.rs` | 61 | - | ⬜ 未开始 |  |
| `core/src/session/step_settings.rs` | 347 | - | ⬜ 未开始 |  |
| `core/src/session/submission.rs` | 18 | - | ⬜ 未开始 |  |
| `core/src/session/thread_settings.rs` | 131 | - | ⬜ 未开始 |  |
| `core/src/session/time_reminder.rs` | 202 | - | ⬜ 未开始 |  |
| `core/src/session/token_budget.rs` | 249 | - | ⬜ 未开始 |  |
| `core/src/session/turn.rs` | 3,113 | `session/turn.swift` | 🟡 partial |  |
| `core/src/session/turn_context.rs` | 1,388 | - | ⬜ 未开始 |  |
| `core/src/session/turn_input.rs` | 780 | - | ⬜ 未开始 |  |
| `core/src/session/turn_suspension.rs` | 119 | - | ⬜ 未开始 |  |
| `core/src/session/world_state.rs` | 335 | - | ⬜ 未开始 |  |
| `core/src/state/additional_context.rs` | 35 | - | ⬜ 未开始 |  |
| `core/src/state/auto_compact_window.rs` | 237 | - | ⬜ 未开始 |  |
| `core/src/state/mod.rs` | 22 | - | ⬜ 未开始 |  |
| `core/src/state/service.rs` | 104 | - | ⬜ 未开始 |  |
| `core/src/state/session.rs` | 478 | - | ⬜ 未开始 |  |
| `core/src/state/turn.rs` | 254 | - | ⬜ 未开始 |  |
| `core/src/state/turn_token_usage.rs` | 48 | - | ⬜ 未开始 |  |
| `core/src/stream_events_utils.rs` | 602 | - | ⬜ 未开始 |  |
| `core/src/tasks/compact.rs` | 76 | `tasks/compact.swift` | 🟡 partial |  |
| `core/src/tasks/lifecycle.rs` | 119 | - | ⬜ 未开始 |  |
| `core/src/tasks/mod.rs` | 1,014 | - | ⬜ 未开始 |  |
| `core/src/tasks/regular.rs` | 126 | `tasks/regular.swift` | 🟡 adapted |  |
| `core/src/tasks/review.rs` | 280 | - | ⬜ 未开始 |  |
| `core/src/tasks/user_shell.rs` | 489 | - | ⬜ 未开始 |  |
| `core/src/turn_diff_tracker.rs` | 403 | - | ⬜ 未开始 |  |
| `core/src/turn_metadata.rs` | 569 | - | ⬜ 未开始 |  |
| `core/src/turn_timing.rs` | 443 | - | ⬜ 未开始 |  |

## Phase 6

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/client.rs` | 2,942 | - | ⬜ 未开始 |  |
| `core/src/client_common.rs` | 141 | - | ⬜ 未开始 |  |
| `core/src/client_tool_metadata.rs` | 45 | - | ⬜ 未开始 |  |
| `core/src/current_time.rs` | 55 | - | ⬜ 未开始 |  |
| `core/src/image_preparation.rs` | 428 | - | ⬜ 未开始 |  |
| `core/src/model_request.rs` | 51 | - | ⬜ 未开始 |  |
| `core/src/original_image_detail.rs` | 2 | - | ⬜ 未开始 |  |
| `core/src/prompt_debug.rs` | 114 | - | ⬜ 未开始 |  |
| `core/src/responses_headers.rs` | 24 | - | ⬜ 未开始 |  |
| `core/src/responses_metadata.rs` | 601 | - | ⬜ 未开始 |  |
| `core/src/responses_retry.rs` | 185 | - | ⬜ 未开始 |  |
| `core/src/web_search.rs` | 30 | - | ⬜ 未开始 |  |
| `codex-api/src/api_bridge.rs` | 343 | - | ⬜ 未开始 |  |
| `codex-api/src/auth.rs` | 104 | - | ⬜ 未开始 |  |
| `codex-api/src/common.rs` | 424 | - | ⬜ 未开始 |  |
| `codex-api/src/endpoint/images.rs` | 411 | - | ⬜ 未开始 |  |
| `codex-api/src/endpoint/memories.rs` | 225 | - | ⬜ 未开始 |  |
| `codex-api/src/endpoint/mod.rs` | 34 | - | ⬜ 未开始 |  |
| `codex-api/src/endpoint/models.rs` | 431 | - | ⬜ 未开始 |  |
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
| `codex-api/src/endpoint/responses.rs` | 159 | - | ⬜ 未开始 |  |
| `codex-api/src/endpoint/responses_websocket.rs` | 1,251 | - | 💤 deferred | 语音/websocket 子集，Phase 10 |
| `codex-api/src/endpoint/search.rs` | 320 | - | ⬜ 未开始 |  |
| `codex-api/src/endpoint/session.rs` | 156 | - | ⬜ 未开始 |  |
| `codex-api/src/error.rs` | 63 | - | ⬜ 未开始 |  |
| `codex-api/src/files.rs` | 892 | - | ⬜ 未开始 |  |
| `codex-api/src/images.rs` | 68 | - | ⬜ 未开始 |  |
| `codex-api/src/lib.rs` | 120 | - | ⬜ 未开始 |  |
| `codex-api/src/provider.rs` | 67 | - | ⬜ 未开始 |  |
| `codex-api/src/rate_limits.rs` | 382 | - | ⬜ 未开始 |  |
| `codex-api/src/requests/headers.rs` | 40 | - | ⬜ 未开始 |  |
| `codex-api/src/requests/mod.rs` | 4 | - | ⬜ 未开始 |  |
| `codex-api/src/requests/responses.rs` | 6 | - | ⬜ 未开始 |  |
| `codex-api/src/safety_buffering.rs` | 67 | - | ⬜ 未开始 |  |
| `codex-api/src/search.rs` | 305 | - | ⬜ 未开始 |  |
| `codex-api/src/sse/mod.rs` | 5 | - | ⬜ 未开始 |  |
| `codex-api/src/sse/responses.rs` | 2,153 | - | ⬜ 未开始 |  |
| `codex-api/src/telemetry.rs` | 98 | - | ⬜ 未开始 |  |
| `model-provider-info/src/gateway_oauth.rs` | 157 | - | ⬜ 未开始 |  |
| `model-provider-info/src/lib.rs` | 765 | - | ⬜ 未开始 |  |

## Phase 7

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/attestation.rs` | 26 | - | ⬜ 未开始 |  |
| `core/src/codex_delegate.rs` | 382 | - | ⬜ 未开始 |  |
| `core/src/codex_thread.rs` | 1,134 | - | ⬜ 未开始 |  |
| `core/src/feedback_config.rs` | 81 | - | ⬜ 未开始 |  |
| `core/src/installation_id.rs` | 149 | - | ⬜ 未开始 |  |
| `core/src/memory_usage.rs` | 51 | - | ⬜ 未开始 |  |
| `core/src/rollout.rs` | 61 | - | ⬜ 未开始 |  |
| `core/src/rollout_budget.rs` | 121 | - | ⬜ 未开始 |  |
| `core/src/session_prefix.rs` | 50 | - | ⬜ 未开始 |  |
| `core/src/session_rollout_init_error.rs` | 67 | - | ⬜ 未开始 |  |
| `core/src/state_db_bridge.rs` | 8 | - | ⬜ 未开始 |  |
| `core/src/thread_manager/managed.rs` | 109 | - | ⬜ 未开始 |  |
| `core/src/thread_manager/shared_instructions.rs` | 112 | - | ⬜ 未开始 |  |
| `core/src/thread_manager.rs` | 2,664 | - | ⬜ 未开始 |  |
| `core/src/thread_rollout_truncation.rs` | 305 | - | ⬜ 未开始 |  |
| `core/src/thread_startup_metadata.rs` | 110 | - | ⬜ 未开始 |  |
| `rollout/src/compression/error_metrics.rs` | 65 | - | ⬜ 未开始 |  |
| `rollout/src/compression/read_metrics.rs` | 124 | - | ⬜ 未开始 |  |
| `rollout/src/compression.rs` | 1,414 | - | ⬜ 未开始 |  |
| `rollout/src/config.rs` | 101 | - | ⬜ 未开始 |  |
| `rollout/src/lib.rs` | 171 | - | ⬜ 未开始 |  |
| `rollout/src/list.rs` | 1,703 | - | ⬜ 未开始 |  |
| `rollout/src/maintenance.rs` | 41 | - | ⬜ 未开始 |  |
| `rollout/src/metadata.rs` | 491 | - | ⬜ 未开始 |  |
| `rollout/src/model_context.rs` | 59 | - | ⬜ 未开始 |  |
| `rollout/src/ordinal.rs` | 131 | - | ⬜ 未开始 |  |
| `rollout/src/persistence_metrics.rs` | 439 | - | ⬜ 未开始 |  |
| `rollout/src/policy.rs` | 206 | - | ⬜ 未开始 |  |
| `rollout/src/recorder.rs` | 2,249 | - | ⬜ 未开始 |  |
| `rollout/src/reverse_jsonl_scanner.rs` | 165 | - | ⬜ 未开始 |  |
| `rollout/src/rollout_file_name.rs` | 87 | - | ⬜ 未开始 |  |
| `rollout/src/rollout_reference_index.rs` | 168 | - | ⬜ 未开始 |  |
| `rollout/src/search.rs` | 370 | - | ⬜ 未开始 |  |
| `rollout/src/seekable_reader.rs` | 110 | - | ⬜ 未开始 |  |
| `rollout/src/session_index.rs` | 300 | - | ⬜ 未开始 |  |
| `rollout/src/sqlite_metrics.rs` | 73 | - | ⬜ 未开始 |  |
| `rollout/src/state_db.rs` | 744 | - | ⬜ 未开始 |  |
| `rollout/src/writer_lock.rs` | 200 | - | ⬜ 未开始 |  |
| `state/src/audit.rs` | 48 | - | ⬜ 未开始 |  |
| `state/src/extract.rs` | 850 | - | ⬜ 未开始 |  |
| `state/src/lib.rs` | 153 | - | ⬜ 未开始 |  |
| `state/src/log_db.rs` | 969 | - | ⬜ 未开始 |  |
| `state/src/migrations.rs` | 122 | - | ⬜ 未开始 |  |
| `state/src/model/backfill_state.rs` | 73 | - | ⬜ 未开始 |  |
| `state/src/model/graph.rs` | 11 | - | ⬜ 未开始 |  |
| `state/src/model/log.rs` | 57 | - | ⬜ 未开始 |  |
| `state/src/model/memories.rs` | 69 | - | ⬜ 未开始 |  |
| `state/src/model/mod.rs` | 56 | - | ⬜ 未开始 |  |
| `state/src/model/project.rs` | 39 | - | ⬜ 未开始 |  |
| `state/src/model/queued_item.rs` | 22 | - | ⬜ 未开始 |  |
| `state/src/model/rollout_migration_state.rs` | 67 | - | ⬜ 未开始 |  |
| `state/src/model/thread_attachment.rs` | 48 | - | ⬜ 未开始 |  |
| `state/src/model/thread_goal.rs` | 117 | - | ⬜ 未开始 |  |
| `state/src/model/thread_metadata.rs` | 894 | - | ⬜ 未开始 |  |
| `state/src/paths.rs` | 9 | - | ⬜ 未开始 |  |
| `state/src/runtime/backfill.rs` | 288 | - | ⬜ 未开始 |  |
| `state/src/runtime/external_agent_config_imports.rs` | 148 | - | ⬜ 未开始 |  |
| `state/src/runtime/goals.rs` | 1,728 | - | ⬜ 未开始 |  |
| `state/src/runtime/logs.rs` | 1,915 | - | ⬜ 未开始 |  |
| `state/src/runtime/memories.rs` | 5,468 | - | ⬜ 未开始 |  |
| `state/src/runtime/memory_readiness.rs` | 16 | - | ⬜ 未开始 |  |
| `state/src/runtime/memory_versions.rs` | 56 | - | ⬜ 未开始 |  |
| `state/src/runtime/projects.rs` | 573 | - | ⬜ 未开始 |  |
| `state/src/runtime/queued_items.rs` | 215 | - | ⬜ 未开始 |  |
| `state/src/runtime/recovery.rs` | 243 | - | ⬜ 未开始 |  |
| `state/src/runtime/remote_control.rs` | 393 | - | ⬜ 未开始 |  |
| `state/src/runtime/rollout_migration.rs` | 149 | - | ⬜ 未开始 |  |
| `state/src/runtime/test_support.rs` | 84 | - | ⬜ 未开始 |  |
| `state/src/runtime/thread_attachments.rs` | 291 | - | ⬜ 未开始 |  |
| `state/src/runtime/thread_section_order.rs` | 284 | - | ⬜ 未开始 |  |
| `state/src/runtime/thread_sections.rs` | 93 | - | ⬜ 未开始 |  |
| `state/src/runtime/threads.rs` | 3,637 | - | ⬜ 未开始 |  |
| `state/src/runtime.rs` | 764 | - | ⬜ 未开始 |  |
| `state/src/sqlite.rs` | 332 | - | ⬜ 未开始 |  |
| `state/src/telemetry.rs` | 251 | - | ⬜ 未开始 |  |
| `thread-store/src/error.rs` | 55 | - | ⬜ 未开始 |  |
| `thread-store/src/in_memory.rs` | 1,181 | - | ⬜ 未开始 |  |
| `thread-store/src/lib.rs` | 114 | - | ⬜ 未开始 |  |
| `thread-store/src/live_thread.rs` | 463 | - | ⬜ 未开始 |  |
| `thread-store/src/local/archive_thread.rs` | 371 | - | ⬜ 未开始 |  |
| `thread-store/src/local/create_thread.rs` | 68 | - | ⬜ 未开始 |  |
| `thread-store/src/local/delete_thread.rs` | 883 | - | ⬜ 未开始 |  |
| `thread-store/src/local/helpers.rs` | 385 | - | ⬜ 未开始 |  |
| `thread-store/src/local/list_threads.rs` | 793 | - | ⬜ 未开始 |  |
| `thread-store/src/local/live_writer.rs` | 374 | - | ⬜ 未开始 |  |
| `thread-store/src/local/mod.rs` | 2,141 | - | ⬜ 未开始 |  |
| `thread-store/src/local/model_context.rs` | 193 | - | ⬜ 未开始 |  |
| `thread-store/src/local/move_thread_to_section.rs` | 58 | - | ⬜ 未开始 |  |
| `thread-store/src/local/paginated_fork.rs` | 191 | - | ⬜ 未开始 |  |
| `thread-store/src/local/pending_thread_metadata.rs` | 58 | - | ⬜ 未开始 |  |
| `thread-store/src/local/projects.rs` | 192 | - | ⬜ 未开始 |  |
| `thread-store/src/local/read_thread.rs` | 1,641 | - | ⬜ 未开始 |  |
| `thread-store/src/local/revert_thread.rs` | 208 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_lineage.rs` | 304 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/canonicalizer.rs` | 502 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/legacy_event.rs` | 314 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/line_parser.rs` | 201 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/publish.rs` | 267 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/rollback.rs` | 147 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/rollback_plan.rs` | 554 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/rollback_replay.rs` | 195 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/startup.rs` | 412 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/subagent.rs` | 55 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration/telemetry.rs` | 152 | - | ⬜ 未开始 |  |
| `thread-store/src/local/rollout_migration.rs` | 1,386 | - | ⬜ 未开始 |  |
| `thread-store/src/local/search_threads.rs` | 257 | - | ⬜ 未开始 |  |
| `thread-store/src/local/test_support.rs` | 131 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_attachments.rs` | 116 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_history/read.rs` | 432 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_history/realtime.rs` | 246 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_history/search.rs` | 494 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_history/segment_paging.rs` | 506 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_history/turn_lookup.rs` | 100 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_history.rs` | 579 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_history_materialization.rs` | 366 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_rollout_resolver.rs` | 216 | - | ⬜ 未开始 |  |
| `thread-store/src/local/thread_sections.rs` | 99 | - | ⬜ 未开始 |  |
| `thread-store/src/local/unarchive_thread.rs` | 286 | - | ⬜ 未开始 |  |
| `thread-store/src/local/update_thread_metadata.rs` | 2,431 | - | ⬜ 未开始 |  |
| `thread-store/src/projects.rs` | 81 | - | ⬜ 未开始 |  |
| `thread-store/src/queue_store.rs` | 158 | - | ⬜ 未开始 |  |
| `thread-store/src/store.rs` | 554 | - | ⬜ 未开始 |  |
| `thread-store/src/thread_attachments.rs` | 39 | - | ⬜ 未开始 |  |
| `thread-store/src/thread_metadata_sync.rs` | 928 | - | ⬜ 未开始 |  |
| `thread-store/src/thread_sections.rs` | 52 | - | ⬜ 未开始 |  |
| `thread-store/src/types.rs` | 1,127 | - | ⬜ 未开始 |  |

## Phase 8

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/agents_md.rs` | 562 | - | ⬜ 未开始 |  |
| `core/src/agents_md_manager.rs` | 182 | - | ⬜ 未开始 |  |
| `core/src/elicitation.rs` | 100 | - | ⬜ 未开始 |  |
| `core/src/guardian/approval_request.rs` | 570 | `guardian/approval_request.swift` | 🟡 partial |  |
| `core/src/guardian/coverage.rs` | 37 | `guardian/coverage.swift` | ✅ faithful |  |
| `core/src/guardian/decision.rs` | 133 | `guardian/decision.swift` | 🟡 partial |  |
| `core/src/guardian/feedback.rs` | 44 | `guardian/feedback.swift` | ✅ faithful |  |
| `core/src/guardian/input_budget.rs` | 198 | `guardian/input_budget.swift` | 🟡 partial |  |
| `core/src/guardian/mod.rs` | 210 | - | ⬜ 未开始 |  |
| `core/src/guardian/permissions.rs` | 109 | - | ⬜ 未开始 |  |
| `core/src/guardian/prompt.rs` | 315 | `guardian/prompt.swift` | 🟡 partial |  |
| `core/src/guardian/request_budget.rs` | 90 | `guardian/request_budget.swift` | 🟡 partial |  |
| `core/src/guardian/review.rs` | 291 | `guardian/review.swift` | 🟡 partial |  |
| `core/src/guardian/review_request.rs` | 266 | `guardian/review_request.swift` | 🟡 partial |  |
| `core/src/guardian/review_session.rs` | 944 | `guardian/review_session.swift` | 🟡 partial |  |
| `core/src/guardian/review_session_context.rs` | 73 | `guardian/review_session_context.swift` | 🟡 partial |  |
| `core/src/guardian/review_session_setup.rs` | 265 | `guardian/review_session_setup.swift` | 🟡 partial |  |
| `core/src/guardian/reviewer_config.rs` | 109 | `guardian/reviewer_config.swift` | 🟡 partial |  |
| `core/src/guardian/runtime.rs` | 89 | `guardian/runtime.swift` | 🟡 partial |  |
| `core/src/guardian_review.rs` | 7 | - | ⬜ 未开始 |  |
| `core/src/hook_mcp_executor.rs` | 57 | - | ⬜ 未开始 |  |
| `core/src/hook_runtime.rs` | 1,353 | `hook_runtime.swift` | 🟡 partial |  |
| `core/src/mention_syntax.rs` | 2 | - | ⬜ 未开始 |  |
| `core/src/skills.rs` | 210 | - | ⬜ 未开始 |  |
| `agent-roles/src/agent_role_config.rs` | 209 | - | ⬜ 未开始 |  |
| `agent-roles/src/discovery.rs` | 40 | - | ⬜ 未开始 |  |
| `agent-roles/src/lib.rs` | 8 | - | ⬜ 未开始 |  |
| `agent-roles/src/loader.rs` | 335 | - | ⬜ 未开始 |  |
| `context-fragments/src/additional_context.rs` | 102 | - | ⬜ 未开始 |  |
| `context-fragments/src/annotated_content.rs` | 98 | - | ⬜ 未开始 |  |
| `context-fragments/src/answered_question.rs` | 60 | - | ⬜ 未开始 |  |
| `context-fragments/src/fragment.rs` | 135 | - | ⬜ 未开始 |  |
| `context-fragments/src/lib.rs` | 16 | - | ⬜ 未开始 |  |
| `context-fragments/src/recap_prompt.rs` | 67 | - | ⬜ 未开始 |  |
| `hooks/src/bin/write_hooks_schema_fixtures.rs` | 9 | - | ⬜ 未开始 |  |
| `hooks/src/config_rules.rs` | 259 | - | ⬜ 未开始 |  |
| `hooks/src/declarations.rs` | 102 | - | ⬜ 未开始 |  |
| `hooks/src/engine/command_runner.rs` | 467 | - | ⬜ 未开始 |  |
| `hooks/src/engine/discovery.rs` | 1,741 | - | ⬜ 未开始 |  |
| `hooks/src/engine/dispatcher.rs` | 656 | - | ⬜ 未开始 |  |
| `hooks/src/engine/mcp_runner.rs` | 166 | - | ⬜ 未开始 |  |
| `hooks/src/engine/mod.rs` | 492 | - | ⬜ 未开始 |  |
| `hooks/src/engine/output_parser.rs` | 617 | - | ⬜ 未开始 |  |
| `hooks/src/engine/schema_loader.rs` | 168 | - | ⬜ 未开始 |  |
| `hooks/src/events/common.rs` | 306 | - | ⬜ 未开始 |  |
| `hooks/src/events/compact.rs` | 554 | - | ⬜ 未开始 |  |
| `hooks/src/events/interrupt.rs` | 183 | - | ⬜ 未开始 |  |
| `hooks/src/events/mod.rs` | 10 | - | ⬜ 未开始 |  |
| `hooks/src/events/permission_request.rs` | 337 | - | ⬜ 未开始 |  |
| `hooks/src/events/post_tool_use.rs` | 637 | - | ⬜ 未开始 |  |
| `hooks/src/events/pre_tool_use.rs` | 820 | - | ⬜ 未开始 |  |
| `hooks/src/events/session_end.rs` | 139 | - | ⬜ 未开始 |  |
| `hooks/src/events/session_start.rs` | 573 | - | ⬜ 未开始 |  |
| `hooks/src/events/stop.rs` | 723 | - | ⬜ 未开始 |  |
| `hooks/src/events/user_prompt_submit.rs` | 492 | - | ⬜ 未开始 |  |
| `hooks/src/legacy_notify.rs` | 183 | - | ⬜ 未开始 |  |
| `hooks/src/lib.rs` | 123 | - | ⬜ 未开始 |  |
| `hooks/src/mcp.rs` | 24 | - | ⬜ 未开始 |  |
| `hooks/src/output_spill.rs` | 135 | - | ⬜ 未开始 |  |
| `hooks/src/registry.rs` | 336 | - | ⬜ 未开始 |  |
| `hooks/src/schema.rs` | 1,254 | - | ⬜ 未开始 |  |
| `hooks/src/types.rs` | 152 | - | ⬜ 未开始 |  |
| `skills/src/interface.rs` | 201 | - | ⬜ 未开始 |  |
| `skills/src/invocation.rs` | 160 | - | ⬜ 未开始 |  |
| `skills/src/lib.rs` | 214 | - | ⬜ 未开始 |  |
| `skills/src/loading.rs` | 119 | - | ⬜ 未开始 |  |
| `skills/src/mentions.rs` | 232 | - | ⬜ 未开始 |  |
| `skills/src/model.rs` | 112 | - | ⬜ 未开始 |  |
| `skills/src/name_counts.rs` | 25 | - | ⬜ 未开始 |  |
| `skills/src/parser.rs` | 225 | - | ⬜ 未开始 |  |
| `skills/src/selection.rs` | 205 | - | ⬜ 未开始 |  |

## Phase 9

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/agent/agent_resolver.rs` | 30 | - | ⬜ 未开始 |  |
| `core/src/agent/api.rs` | 234 | - | ⬜ 未开始 |  |
| `core/src/agent/child_config.rs` | 365 | - | ⬜ 未开始 |  |
| `core/src/agent/control/api.rs` | 307 | - | ⬜ 未开始 |  |
| `core/src/agent/control/budget.rs` | 39 | - | ⬜ 未开始 |  |
| `core/src/agent/control/completion.rs` | 131 | - | ⬜ 未开始 |  |
| `core/src/agent/control/delivery.rs` | 43 | - | ⬜ 未开始 |  |
| `core/src/agent/control/execution.rs` | 90 | - | ⬜ 未开始 |  |
| `core/src/agent/control/inspection.rs` | 32 | - | ⬜ 未开始 |  |
| `core/src/agent/control/interrupt.rs` | 52 | - | ⬜ 未开始 |  |
| `core/src/agent/control/legacy.rs` | 124 | - | ⬜ 未开始 |  |
| `core/src/agent/control/residency.rs` | 276 | - | ⬜ 未开始 |  |
| `core/src/agent/control/resume.rs` | 37 | - | ⬜ 未开始 |  |
| `core/src/agent/control/runtime.rs` | 130 | - | ⬜ 未开始 |  |
| `core/src/agent/control/runtime_context.rs` | 137 | - | ⬜ 未开始 |  |
| `core/src/agent/control/sender_context.rs` | 84 | - | ⬜ 未开始 |  |
| `core/src/agent/control/service_tier.rs` | 21 | - | ⬜ 未开始 |  |
| `core/src/agent/control/spawn.rs` | 1,433 | - | ⬜ 未开始 |  |
| `core/src/agent/control/spawn_guard.rs` | 75 | - | ⬜ 未开始 |  |
| `core/src/agent/control/spawn_telemetry.rs` | 65 | - | ⬜ 未开始 |  |
| `core/src/agent/control/target.rs` | 61 | - | ⬜ 未开始 |  |
| `core/src/agent/control/user_authorization.rs` | 355 | - | ⬜ 未开始 |  |
| `core/src/agent/control/watch.rs` | 65 | - | ⬜ 未开始 |  |
| `core/src/agent/control.rs` | 699 | - | ⬜ 未开始 |  |
| `core/src/agent/mod.rs` | 14 | - | ⬜ 未开始 |  |
| `core/src/agent/registry.rs` | 399 | - | ⬜ 未开始 |  |
| `core/src/agent/role.rs` | 418 | - | ⬜ 未开始 |  |
| `core/src/agent/status.rs` | 31 | - | ⬜ 未开始 |  |
| `core/src/agent/types.rs` | 88 | - | ⬜ 未开始 |  |
| `core/src/agent_communication.rs` | 78 | - | ⬜ 未开始 |  |
| `core/src/agent_message_board.rs` | 200 | - | ⬜ 未开始 |  |
| `core/src/apps/mod.rs` | 2 | - | ⬜ 未开始 |  |
| `core/src/apps/render.rs` | 66 | - | ⬜ 未开始 |  |
| `core/src/connectors.rs` | 555 | - | ⬜ 未开始 |  |
| `core/src/cyber_access_program.rs` | 12 | - | ⬜ 未开始 |  |
| `core/src/environment_selection.rs` | 2,311 | - | ⬜ 未开始 |  |
| `core/src/plugins/discoverable.rs` | 59 | - | ⬜ 未开始 |  |
| `core/src/plugins/injection.rs` | 59 | - | ⬜ 未开始 |  |
| `core/src/plugins/mentions.rs` | 121 | - | ⬜ 未开始 |  |
| `core/src/plugins/metrics.rs` | 62 | - | ⬜ 未开始 |  |
| `core/src/plugins/mod.rs` | 46 | - | ⬜ 未开始 |  |
| `core/src/plugins/render.rs` | 92 | - | ⬜ 未开始 |  |
| `core/src/plugins/test_support.rs` | 109 | - | ⬜ 未开始 |  |
| `core/src/session/multi_agents.rs` | 121 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/delegate.rs` | 497 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/execute_handler.rs` | 259 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/execute_spec.rs` | 105 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/mod.rs` | 567 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/output.rs` | 76 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/response_adapter.rs` | 51 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/telemetry.rs` | 158 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/wait_handler.rs` | 230 | - | ⬜ 未开始 |  |
| `core/src/tools/code_mode/wait_spec.rs` | 126 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/list_available_plugins_to_install.rs` | 181 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/list_available_plugins_to_install_spec.rs` | 45 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents/close_agent.rs` | 137 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents/resume_agent.rs` | 171 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents/send_input.rs` | 173 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents/spawn.rs` | 249 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents/wait.rs` | 341 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents.rs` | 99 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_common.rs` | 190 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_spec.rs` | 891 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/analytics.rs` | 62 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/followup_task.rs` | 57 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/interrupt_agent.rs` | 110 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/list_agents.rs` | 110 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/message_tool.rs` | 99 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/send_message.rs` | 57 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/spawn.rs` | 338 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2/wait.rs` | 205 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/multi_agents_v2.rs` | 66 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/request_plugin_install.rs` | 551 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/request_plugin_install_spec.rs` | 189 | - | ⬜ 未开始 |  |
| `core/src/tools/handlers/wait_for_environment.rs` | 182 | - | ⬜ 未开始 |  |

## Phase 10

| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |
|---|---:|---|---|---|
| `core/src/context/realtime_delegation.rs` | 105 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/context/realtime_end_instructions.rs` | 51 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/context/realtime_start_instructions.rs` | 33 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/context/realtime_start_with_instructions.rs` | 42 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/lib.rs` | 246 | - | ⬜ 未开始 |  |
| `core/src/otel_init.rs` | 111 | - | ⬜ 未开始 |  |
| `core/src/realtime_context.rs` | 583 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation/bem.rs` | 71 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation/existing_call.rs` | 90 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation/sideband.rs` | 195 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_conversation.rs` | 2,752 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_history/presentation.rs` | 129 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_history.rs` | 450 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/realtime_prompt.rs` | 82 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/session/realtime_history.rs` | 56 | - | ⬜ 未开始 | deferred: 语音 realtime，Sage 无此形态 |
| `core/src/test_support.rs` | 264 | - | ⬜ 未开始 |  |
| `otel/src/agent_response.rs` | 111 | - | ⬜ 未开始 |  |
| `otel/src/auth_storage/originator.rs` | 45 | - | ⬜ 未开始 |  |
| `otel/src/auth_storage.rs` | 257 | - | ⬜ 未开始 |  |
| `otel/src/config.rs` | 120 | - | ⬜ 未开始 |  |
| `otel/src/events/mod.rs` | 2 | - | ⬜ 未开始 |  |
| `otel/src/events/session_telemetry.rs` | 1,429 | - | ⬜ 未开始 |  |
| `otel/src/events/shared.rs` | 70 | - | ⬜ 未开始 |  |
| `otel/src/guardian_assessment.rs` | 68 | - | ⬜ 未开始 |  |
| `otel/src/lib.rs` | 99 | - | ⬜ 未开始 |  |
| `otel/src/metrics/buffered.rs` | 177 | - | ⬜ 未开始 |  |
| `otel/src/metrics/client.rs` | 678 | - | ⬜ 未开始 |  |
| `otel/src/metrics/config.rs` | 135 | - | ⬜ 未开始 |  |
| `otel/src/metrics/error.rs` | 49 | - | ⬜ 未开始 |  |
| `otel/src/metrics/mod.rs` | 61 | - | ⬜ 未开始 |  |
| `otel/src/metrics/names.rs` | 80 | - | ⬜ 未开始 |  |
| `otel/src/metrics/process.rs` | 27 | - | ⬜ 未开始 |  |
| `otel/src/metrics/runtime_metrics.rs` | 220 | - | ⬜ 未开始 |  |
| `otel/src/metrics/tags.rs` | 134 | - | ⬜ 未开始 |  |
| `otel/src/metrics/timer.rs` | 41 | - | ⬜ 未开始 |  |
| `otel/src/metrics/validation.rs` | 55 | - | ⬜ 未开始 |  |
| `otel/src/network_policy.rs` | 127 | - | ⬜ 未开始 |  |
| `otel/src/otlp.rs` | 277 | - | ⬜ 未开始 |  |
| `otel/src/provider.rs` | 854 | - | ⬜ 未开始 |  |
| `otel/src/targets.rs` | 11 | - | ⬜ 未开始 |  |
| `otel/src/tool_result.rs` | 115 | - | ⬜ 未开始 |  |
| `otel/src/trace_context.rs` | 411 | - | ⬜ 未开始 |  |
| `terminal-detection/src/lib.rs` | 423 | - | ⬜ 未开始 |  |

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
| `async-utils/src/cancellation_token.swift` | Sage 新增，无 codex 对应 |
| `protocol/src/json_value.swift` | Sage 新增，无 codex 对应 |
| `protocol/src/serde_helpers.swift` | Sage 新增，无 codex 对应 |
| `protocol/src/uuid_v7.swift` | Sage 新增，无 codex 对应 |
| `tasks/explore.swift` | Sage 新增，无 codex 对应 |
| `utils/io_error.swift` | Sage 新增，无 codex 对应 |
| `utils/path-uri/src/file_url.swift` | Sage 新增，无 codex 对应 |
| `utils/path-uri/src/url_encoding.swift` | Sage 新增，无 codex 对应 |
