#!/usr/bin/env python3
"""harness_port.py — codex → Swift 移植追踪与 lint（EXECUTE_HARNESS_PORT_PLAN.md Phase 0）

用法（在 Sage 仓库根目录执行）：
  python3 scripts/harness_port.py generate   # 生成/更新 Harness/PORTING.md（保留已有状态与备注）
  python3 scripts/harness_port.py check      # lint 文件头 + 覆盖完整性 + 表一致性，有违规退出码 1
  python3 scripts/harness_port.py stats      # 打印分 phase 进度统计

约定（计划 §5）：
  codex-rs/core/src/<path>.rs        → Sage/Agent/Execute/Harness/<path>.swift
  codex-rs/<crate>/src/<path>.rs     → Sage/Agent/Execute/Harness/<crate>/src/<path>.swift
  mod.rs → mod.swift；文件名保持 snake_case；一个 Rust 文件对应一个 Swift 文件。
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CODEX = ROOT.parent / "codex" / "codex-rs"
HARNESS = ROOT / "Sage" / "Agent" / "Execute" / "Harness"
PORTING = HARNESS / "PORTING.md"
FALLBACK_REVISION = "0a2eb4696c26ac33204bcd255721ab30220a4774"

STATUSES = ["faithful", "adapted", "partial", "stub", "not-started"]
STATUS_LABEL = {
    "faithful": "✅ faithful",
    "adapted": "🟡 adapted",
    "partial": "🟡 partial",
    "stub": "🟥 stub",
    "not-started": "⬜ 未开始",
    "excluded": "⛔ excluded",
    "deferred": "💤 deferred",
}

# ---------------------------------------------------------------------------
# 范围定义（与 EXECUTE_HARNESS_PORT_PLAN.md §2 / §7 一致）
# ---------------------------------------------------------------------------

# crate → phase
CRATES = {
    "protocol": 1,
    "async-utils": 1,
    "utils/absolute-path": 1,
    "utils/path-uri": 1,
    "utils/path-utils": 1,
    "utils/output-truncation": 1,
    "utils/string": 1,
    "utils/stream-parser": 1,
    "utils/cache": 1,
    "utils/home-dir": 1,
    "utils/git-discovery": 1,
    "utils/image": 1,
    "utils/audio": 1,
    "utils/plugins": 1,
    "file-system": 2,
    "apply-patch": 2,
    "git-utils": 2,
    "utils/pty": 3,
    "sandboxing": 3,
    "shell-command": 3,
    "execpolicy": 3,
    "network-proxy": 4,
    "model-provider-info": 6,
    "codex-api": 6,
    "rollout": 7,
    "state": 7,
    "thread-store": 7,
    "hooks": 8,
    "skills": 8,
    "agent-roles": 8,
    "context-fragments": 8,
    "otel": 10,
    "terminal-detection": 10,
}

# core 内平台排除（不建 Swift 文件）
CORE_EXCLUDED = {
    "windows_sandbox.rs": "platform: Windows 沙盒",
    "windows_sandbox_read_grants.rs": "platform: Windows 沙盒",
    "windows_system_config.rs": "platform: Windows 沙盒",
}
# core 内测试支撑（不移植）
CORE_TEST_ONLY = {
    "guardian/test_host.rs",
    "context/world_state/test_support.rs",
}

CORE_P3 = {
    "exec.rs", "exec_env.rs", "exec_policy.rs", "shell.rs", "shell_snapshot.rs",
    "shell_snapshot_sandbox.rs", "spawn.rs", "safety.rs", "sandbox_tags.rs",
    "command_canonicalization.rs", "user_shell_command.rs", "apply_patch.rs",
}
CORE_P5_ROOT = {
    "compact.rs", "compact_model_fallback.rs", "compact_remote_history.rs",
    "compact_remote_v2.rs", "compact_remote_v2_attempt.rs", "compact_remote_v2_images.rs",
    "compact_token_budget.rs", "stream_events_utils.rs", "event_mapping.rs",
    "turn_metadata.rs", "turn_timing.rs", "turn_diff_tracker.rs",
    "mcp.rs", "mcp_tool_call.rs", "mcp_tool_exposure.rs", "mcp_skill_dependencies.rs",
    "mcp_tool_approval_templates.rs", "mcp_openai_file.rs", "session_startup_prewarm.rs",
}
CORE_P6 = {
    "client.rs", "client_common.rs", "client_tool_metadata.rs", "model_request.rs",
    "responses_headers.rs", "responses_metadata.rs",
    "responses_retry.rs", "prompt_debug.rs", "image_preparation.rs",
    "original_image_detail.rs", "current_time.rs", "web_search.rs",
}
CORE_P7 = {
    "thread_manager.rs", "codex_thread.rs", "codex_delegate.rs", "rollout.rs",
    "rollout_budget.rs", "thread_rollout_truncation.rs", "session_prefix.rs",
    "thread_startup_metadata.rs", "session_rollout_init_error.rs", "state_db_bridge.rs",
    "memory_usage.rs", "installation_id.rs", "feedback_config.rs", "attestation.rs",
}
CORE_P8 = {
    "guardian_review.rs", "hook_runtime.rs", "hook_mcp_executor.rs", "skills.rs",
    "agents_md.rs", "agents_md_manager.rs", "elicitation.rs", "mention_syntax.rs",
}
CORE_P9 = {
    "agent_communication.rs", "agent_message_board.rs", "connectors.rs",
    "environment_selection.rs", "cyber_access_program.rs",
}
CORE_P10 = {"otel_init.rs", "lib.rs", "test_support.rs"}


def core_classify(rel: str) -> tuple[int | None, str]:
    """返回 (phase, note)；phase=None 表示不计入范围。"""
    name = rel.rsplit("/", 1)[-1]
    if rel in CORE_EXCLUDED:
        return (None, CORE_EXCLUDED[rel])
    if rel in CORE_TEST_ONLY:
        return (None, "test-only")
    # Phase 10 deferred：语音 realtime
    if name.startswith("realtime_") or rel.startswith("realtime_conversation/") \
            or rel.startswith("realtime_history/") or rel == "session/realtime_history.rs":
        return (10, "deferred: 语音 realtime，Sage 无此形态")
    if rel in CORE_P10:
        return (10, "")
    # Phase 9 需在 4/5 之前判断（子目录优先）
    if rel.startswith("agent/") or rel in CORE_P9:
        return (9, "")
    if rel.startswith("tools/code_mode/") or rel.startswith("plugins/") or rel.startswith("apps/"):
        return (9, "")
    if "multi_agents" in rel or rel == "session/multi_agents.rs":
        return (9, "")
    if rel.startswith("tools/handlers/request_plugin_install") \
            or rel.startswith("tools/handlers/list_available_plugins") \
            or rel == "tools/handlers/wait_for_environment.rs":
        return (9, "")
    # Phase 3
    if rel in CORE_P3 or rel.startswith("unified_exec/") or rel.startswith("exec_policy/") \
            or rel == "sandboxing/mod.rs":
        return (3, "")
    # Phase 4
    if rel.startswith("tools/") or rel in ("function_tool.rs", "network_policy_decision.rs"):
        return (4, "")
    # Phase 8
    if rel.startswith("guardian/") or rel in CORE_P8:
        return (8, "")
    # Phase 7
    if rel in CORE_P7 or rel.startswith("thread_manager/"):
        return (7, "")
    # Phase 6
    if rel in CORE_P6:
        return (6, "")
    # Phase 1：core 自带小工具
    if rel == "util.rs" or rel.startswith("utils/"):
        return (1, "")
    # Phase 5
    if rel in CORE_P5_ROOT or rel.startswith("mcp_tool_call/"):
        return (5, "")
    if rel.startswith(("state/", "session/", "tasks/", "context/", "context_manager/", "config/")):
        return (5, "")
    return (5, "unclassified at generate time; assign phase")


# crate 内文件级规则：rel → (status, note)
CRATE_FILE_RULES: dict[str, dict[str, tuple[str | None, str]]] = {
    "network-proxy": {
        # 仅移植策略类型层（core 的 network_policy.rs 依赖这些类型）；
        # 本地代理进程机械全部排除，见 CRATE_DEFAULT_RULES。
        "config.rs": (None, "策略类型层"),
        "network_policy.rs": (None, "策略类型层"),
        "policy.rs": (None, "策略类型层"),
        "reasons.rs": (None, "策略类型层"),
        "environment_policy.rs": (None, "策略类型层"),
    },
    "sandboxing": {
        "landlock.rs": ("excluded", "platform: Linux"),
        "bwrap.rs": ("excluded", "platform: Linux"),
        "windows.rs": ("excluded", "platform: Windows"),
        "windows_mxc.rs": ("excluded", "platform: Windows"),
    },
    "shell-command": {
        "powershell.rs": ("not-started", "适配项：macOS 仅需 bash/zsh/sh，保留同名文件标注"),
        "command_safety/powershell_parser.rs": ("not-started", "适配项：macOS 不需要 PowerShell 解析"),
        "command_safety/powershell_tree_sitter.rs": ("not-started", "适配项：macOS 不需要 PowerShell 解析"),
        "command_safety/windows_dangerous_commands.rs": ("not-started", "适配项：Windows 危险命令表"),
    },
    "utils/pty": {
        "win/conpty.rs": ("excluded", "platform: Windows PTY"),
        "win/job.rs": ("excluded", "platform: Windows PTY"),
        "win/mod.rs": ("excluded", "platform: Windows PTY"),
        "win/procthreadattr.rs": ("excluded", "platform: Windows PTY"),
        "win/psuedocon.rs": ("excluded", "platform: Windows PTY"),
        "windows_input.rs": ("excluded", "platform: Windows PTY"),
    },
    "execpolicy": {
        "main.rs": ("excluded", "独立 CLI 入口，Sage 不需要"),
    },
    "apply-patch": {
        "standalone_executable.rs": ("not-started", "适配项：Sage 进程内调用，无独立可执行"),
        "main.rs": ("excluded", "独立可执行入口，Sage 不需要"),
    },
}


# crate 级默认规则（文件级规则未命中时生效）：crate → (status, note)
CRATE_DEFAULT_RULES: dict[str, tuple[str, str]] = {
    "network-proxy": ("excluded", "适配: 本地代理进程不移植，仅移植策略类型层（plan §2.3 补记）"),
}


def crate_file_classify(crate: str, rel: str) -> tuple[str | None, str]:
    """返回 (forced_status or None, note)。"""
    rules = CRATE_FILE_RULES.get(crate, {})
    if rel in rules:
        return rules[rel]
    if crate == "codex-api" and ("realtime" in rel or "websocket" in rel):
        return ("deferred", "语音/websocket 子集，Phase 10")
    if crate in CRATE_DEFAULT_RULES:
        return CRATE_DEFAULT_RULES[crate]
    return (None, "")


# ---------------------------------------------------------------------------
# 扫描
# ---------------------------------------------------------------------------

@dataclass
class Row:
    codex: str          # 相对 codex-rs/ 的路径，如 core/src/session/turn.rs
    lines: int
    phase: int | None   # None = 不计入（平台排除/测试）
    swift: str          # 相对 Harness/ 的路径；无对应物时 "-"
    status: str         # faithful/adapted/partial/stub/not-started/excluded/deferred
    note: str = ""


def is_test_file(p: Path) -> bool:
    n = p.name
    return n.endswith("_tests.rs") or n.endswith("_test.rs") or n == "tests.rs" \
        or "tests" in p.parts or "snapshots" in p.parts


def count_lines(p: Path) -> int:
    try:
        return sum(1 for _ in p.open("rb"))
    except OSError:
        return 0


def swift_path_for(codex_rel: str) -> str:
    """codex-rs 相对路径 → Harness 相对路径（§5.1 R1/R2/R3/R4，不含 R4a 冲突消解）。"""
    assert codex_rel.endswith(".rs")
    stem = codex_rel[:-3]
    if stem.startswith("core/src/"):
        return stem[len("core/src/"):] + ".swift"
    # <crate>/src/<rel> → <crate>/src/<rel>.swift
    return stem + ".swift"


_CRATE_TOPS = {c.split("/")[0] for c in CRATES}


def module_of(swift_rel: str) -> str:
    """Swift 文件所属 module（§4.1）；R4a 冲突只在同 module 内发生。

    crate 映射路径形如 `<crate>/src/...`（R2）；core 映射路径第二级永不为
    `src`（R1），借此区分 `core/src/state/mod.rs`（CodexCore）与
    `state/src/model/mod.rs`（state crate 模块）。
    """
    top = swift_rel.split("/", 1)[0]
    if top == "utils":
        return "CodexUtils"
    if top == "async-utils":
        # SPM 一个 target 只能有一个 path，async-utils/ 不在 utils/ 子树内，
        # 独立成 CodexAsyncUtils 模块（§4.1 注记）。
        return "CodexAsyncUtils"
    if top == "protocol":
        return "CodexProtocol"
    if top == "apply-patch":
        return "ApplyPatch"
    if top == "file-system":
        return "FileSystem"
    if top == "git-utils":
        return "CodexGitUtils"
    if top == "sandboxing":
        return "CodexSandboxing"
    if top == "shell-command":
        return "CodexShellCommand"
    if top == "execpolicy":
        return "CodexExecPolicy"
    if swift_rel.startswith("tools/runtimes/"):
        return "ToolsRuntimes"
    parts = swift_rel.split("/")
    if len(parts) >= 3 and parts[1] == "src" and top in _CRATE_TOPS:
        return f"Crate:{top}"
    return "CodexCore"


def collision_prefix(codex_rel: str) -> str:
    """R4a 前缀：crate 文件用 crate 目录名（- → _），core 文件用父目录名。"""
    if codex_rel.startswith("core/src/"):
        parent = codex_rel[len("core/src/"):].rpartition("/")[0]
        return parent.rsplit("/", 1)[-1] if parent else "core"
    crate = codex_rel.split("/src/", 1)[0]
    return crate.rsplit("/", 1)[-1].replace("-", "_")


def resolve_collisions(entries: list[tuple[str, int | None, str, str | None]],
                       existing: dict[str, str] | None = None) -> dict[str, str]:
    """§5.1 R4a：同一 module 内 basename 冲突时，既有文件保留原名（先到先得），
    新增文件加 collision_prefix；同批多个新文件冲突时按 codex 路径排序，首个保留原名。
    只对未来会真正移植的文件（非 excluded/deferred）判定。
    existing：codex_rel → 磁盘上实际 Swift 路径（来自文件头扫描）。"""
    existing = existing or {}
    base: dict[str, str] = {}
    for codex_rel, phase, _note, forced in entries:
        if phase is None or forced in ("excluded", "deferred"):
            continue
        base[codex_rel] = swift_path_for(codex_rel)

    def grandfathered(p: str) -> str | None:
        """既有文件的实际路径可继承：与基础映射同目录，且 basename 相同或带 R4a 前缀。"""
        actual = existing.get(p)
        if not actual:
            return None
        b = base[p]
        b_dir, _, b_name = b.rpartition("/")
        a_dir, _, a_name = actual.rpartition("/")
        if a_dir == b_dir and (a_name == b_name or a_name.endswith("_" + b_name)):
            return actual
        return None

    out: dict[str, str] = {}
    groups: dict[tuple[str, str], list[str]] = {}
    for p, s in base.items():
        groups.setdefault((module_of(s), s.rsplit("/", 1)[-1]), []).append(p)
    for members in groups.values():
        keepers: set[str] = set()
        if len(members) < 2:
            keepers = set(members)
        else:
            inherited = {m: g for m in members if (g := grandfathered(m))}
            if inherited:
                # 既有文件保留实际路径；其余新文件一律加前缀
                for m, g in inherited.items():
                    out[m] = g
                for m in members:
                    if m not in inherited:
                        s = base[m]
                        dirname, _, basename = s.rpartition("/")
                        prefixed = f"{collision_prefix(m)}_{basename}"
                        out[m] = f"{dirname}/{prefixed}" if dirname else prefixed
                continue
            keepers = {sorted(members)[0]}
        for m in members:
            if m in out:
                continue
            g = grandfathered(m)
            if g:
                out[m] = g
                continue
            s = base[m]
            if m in keepers:
                out[m] = s
            else:
                dirname, _, basename = s.rpartition("/")
                prefixed = f"{collision_prefix(m)}_{basename}"
                out[m] = f"{dirname}/{prefixed}" if dirname else prefixed
    return out


def scan_swift_headers() -> dict[str, dict[str, str]]:
    """Harness 下所有 .swift → {port_of, revision, status, addition}。"""
    out: dict[str, dict[str, str]] = {}
    for f in sorted(HARNESS.rglob("*.swift")):
        rel = f.relative_to(HARNESS).as_posix()
        if rel == "Package.swift":
            continue
        head = "\n".join(f.read_text().splitlines()[:24])
        info = {
            "port_of": "",
            "revision": "",
            "status": "",
            "addition": "Sage addition (no codex counterpart)" in head,
        }
        m = re.search(r"Port of (codex-rs/\S+?\.rs)", head)
        if m:
            info["port_of"] = m.group(1)
        m = re.search(r"Upstream revision: ([0-9a-f]{40})", head)
        if m:
            info["revision"] = m.group(1)
        m = re.search(r"Port status: (\w+)", head)
        if m:
            info["status"] = m.group(1)
        out[rel] = info
    return out


def collect_entries() -> list[tuple[str, int | None, str, str | None]]:
    """扫描 codex 树，返回 (codex_rel, phase, note, forced_status) 列表。"""
    entries: list[tuple[str, int | None, str, str | None]] = []
    # core
    for f in sorted((CODEX / "core" / "src").rglob("*.rs")):
        if is_test_file(f.relative_to(CODEX / "core" / "src")):
            continue
        rel = f.relative_to(CODEX / "core" / "src").as_posix()
        phase, note = core_classify(rel)
        entries.append((f"core/src/{rel}", phase, note, None))
    # crates
    for crate, phase in sorted(CRATES.items()):
        src = CODEX / crate / "src"
        if not src.is_dir():
            continue
        for f in sorted(src.rglob("*.rs")):
            rel = f.relative_to(src).as_posix()
            if is_test_file(f.relative_to(src)):
                continue
            forced, note = crate_file_classify(crate, rel)
            entries.append((f"{crate}/src/{rel}", phase, note, forced))
    return entries


def existing_paths(swift: dict[str, dict[str, str]]) -> dict[str, str]:
    """codex_rel → 磁盘上实际 Swift 路径（R4a 先到先得判定用）。"""
    return {v["port_of"].removeprefix("codex-rs/"): k for k, v in swift.items() if v["port_of"]}


def build_rows() -> list[Row]:
    swift = scan_swift_headers()
    entries = collect_entries()
    paths = resolve_collisions(entries, existing_paths(swift))
    rows: list[Row] = []

    def add(codex_rel: str, phase: int | None, note: str, forced: str | None = None):
        swift_rel = paths.get(codex_rel, swift_path_for(codex_rel))
        header = swift.get(swift_rel)
        if header and header["port_of"]:
            status = header["status"] or "partial"
            sp = swift_rel
        else:
            status = forced or ("excluded" if phase is None else "not-started")
            sp = "-"
            if phase is None and not forced:
                status = "excluded"
        if forced == "deferred":
            status = "deferred"
        if phase is None:
            status = "excluded"
        rows.append(Row(codex=codex_rel, lines=count_lines(CODEX / codex_rel),
                        phase=phase, swift=sp, status=status, note=note))

    for codex_rel, phase, note, forced in entries:
        add(codex_rel, phase, note, forced)

    # Sage additions 作为伪行附在末尾（generate 时单独成节）
    for rel, info in swift.items():
        if info["addition"]:
            rows.append(Row(codex="(sage-addition)", lines=0, phase=None,
                            swift=rel, status="sage-addition", note="Sage 新增，无 codex 对应"))
    return rows


# ---------------------------------------------------------------------------
# generate
# ---------------------------------------------------------------------------

def load_existing_notes() -> dict[str, tuple[str, str]]:
    """从已有 PORTING.md 解析 codex 路径 → (status, note)，重新生成时保留手改。"""
    out: dict[str, tuple[str, str]] = {}
    if not PORTING.exists():
        return out
    for line in PORTING.read_text().splitlines():
        m = re.match(r"\| `([^`]+\.rs)` \| [\d,]+ \| [^|]* \| ([^|]+) \| ([^|]*) \|", line)
        if m:
            out[m.group(1)] = (m.group(2).strip(), m.group(3).strip())
    return out


def pinned_revision() -> str:
    try:
        return subprocess.run(["git", "-C", str(CODEX.parent), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return FALLBACK_REVISION


def generate() -> None:
    rows = build_rows()
    existing = load_existing_notes()
    for r in rows:
        if r.codex in existing and r.status in ("not-started", "excluded", "deferred"):
            prev_status, prev_note = existing[r.codex]
            # 手工改过状态/备注的未移植行保留（Swift 文件存在时以文件头为准）
            if r.swift == "-" and prev_status and prev_status != "⬜ 未开始":
                r.status = prev_status
            if prev_note:
                r.note = prev_note

    rev = pinned_revision()
    by_phase: dict[int | None, list[Row]] = {}
    for r in rows:
        by_phase.setdefault(r.phase, []).append(r)

    lines: list[str] = []
    lines.append("# Execute Harness 移植追踪表")
    lines.append("")
    lines.append(f"> 由 `scripts/harness_port.py generate` 生成（{rev[:8]} 基线）。")
    lines.append("> 状态随 PR 手工更新；`check` 模式校验文件头与本表一致。")
    lines.append("> 重新生成会保留未移植行的手工状态与备注；已移植行以 Swift 文件头为准。")
    lines.append("")
    lines.append("状态图例：✅ faithful ｜ 🟡 adapted / partial ｜ 🟥 stub ｜ ⬜ 未开始 ｜ ⛔ excluded(platform/test) ｜ 💤 deferred")
    lines.append("")

    # 汇总
    lines.append("## 进度汇总")
    lines.append("")
    lines.append("| Phase | 文件数 | ✅ | 🟡 | 🟥 | ⬜ | ⛔/💤 |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for phase in sorted(p for p in by_phase if p is not None):
        rs = [r for r in by_phase[phase] if r.status != "sage-addition"]
        n = len(rs)
        fa = sum(1 for r in rs if r.status == "faithful")
        ad = sum(1 for r in rs if r.status in ("adapted", "partial"))
        st = sum(1 for r in rs if r.status == "stub")
        ns = sum(1 for r in rs if r.status == "not-started")
        ex = sum(1 for r in rs if r.status in ("excluded", "deferred"))
        lines.append(f"| Phase {phase} | {n} | {fa} | {ad} | {st} | {ns} | {ex} |")
    lines.append("")

    for phase in sorted(p for p in by_phase if p is not None):
        rs = [r for r in by_phase[phase] if r.status != "sage-addition"]
        lines.append(f"## Phase {phase}")
        lines.append("")
        lines.append("| codex 文件 | 行数 | Swift 文件 | 状态 | 备注 |")
        lines.append("|---|---:|---|---|---|")
        for r in rs:
            swift = f"`{r.swift}`" if r.swift != "-" else "-"
            label = STATUS_LABEL.get(r.status, r.status)
            lines.append(f"| `{r.codex}` | {r.lines:,} | {swift} | {label} | {r.note} |")
        lines.append("")

    excluded = [r for r in rows if r.phase is None and r.status == "excluded"]
    if excluded:
        lines.append("## 不计入范围（平台/测试）")
        lines.append("")
        lines.append("| codex 文件 | 备注 |")
        lines.append("|---|---|")
        for r in excluded:
            lines.append(f"| `{r.codex}` | {r.note} |")
        lines.append("")

    additions = [r for r in rows if r.status == "sage-addition"]
    if additions:
        lines.append("## Sage 新增（无 codex 对应）")
        lines.append("")
        lines.append("| Swift 文件 | 备注 |")
        lines.append("|---|---|")
        for r in additions:
            lines.append(f"| `{r.swift}` | {r.note} |")
        lines.append("")

    PORTING.write_text("\n".join(lines))
    n_rs = sum(1 for r in rows if r.phase is not None)
    n_done = sum(1 for r in rows if r.status in ("faithful", "adapted", "partial", "stub"))
    print(f"PORTING.md 已生成：{n_rs} 个范围内文件，{n_done} 个已有移植，"
          f"{len(excluded)} 个排除，{len(additions)} 个 Sage 新增。")


# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

def check() -> int:
    problems: list[str] = []
    rev = pinned_revision()
    swift = scan_swift_headers()

    # 1) 文件头 lint
    for rel, info in swift.items():
        if info["addition"]:
            continue
        if not info["port_of"]:
            problems.append(f"{rel}: 缺少 `Port of codex-rs/...` 行（或 Sage addition 标记）")
            continue
        upstream = ROOT.parent / info["port_of"].replace("codex-rs/", "codex/codex-rs/")
        if not upstream.exists():
            problems.append(f"{rel}: Port of 指向不存在的上游文件 {info['port_of']}")
        if not info["revision"]:
            problems.append(f"{rel}: 缺少 Upstream revision")
        elif info["revision"] != rev:
            problems.append(f"{rel}: revision {info['revision'][:8]} 与基线 {rev[:8]} 不一致")
        if not info["status"]:
            problems.append(f"{rel}: 缺少 Port status")
        elif info["status"] not in ("faithful", "adapted", "partial", "stub"):
            problems.append(f"{rel}: 非法 Port status `{info['status']}`")

    # 2) 覆盖完整性：范围内每个 .rs 有 Swift 对应物，或被规则排除/暂缓
    rows = build_rows()
    for r in rows:
        if r.status == "sage-addition":
            continue
        if r.phase is not None and r.swift == "-" and r.status == "not-started":
            pass  # 未开始是合法状态，只统计不报错
        if r.swift != "-" and r.swift not in swift:
            problems.append(f"{r.codex}: 追踪表记录的 Swift 文件 {r.swift} 不存在")

    # 3) 反向：每个有 Port of 的 Swift 文件，其上游文件在范围内且路径互指（含 R4a）
    paths = resolve_collisions(collect_entries(), existing_paths(swift))
    for rel, info in swift.items():
        if not info["port_of"]:
            continue
        codex_rel = info["port_of"].removeprefix("codex-rs/")
        expect = paths.get(codex_rel, swift_path_for(codex_rel))
        if expect != rel:
            problems.append(f"{rel}: 与 {codex_rel} 的映射位置应为 {expect}（§5.1）")

    # 4) PORTING.md 新鲜度
    if not PORTING.exists():
        problems.append("PORTING.md 不存在，请先运行 generate")
    else:
        table = PORTING.read_text()
        for r in rows:
            if r.status == "sage-addition":
                if r.swift not in table:
                    problems.append(f"PORTING.md 缺少 Sage 新增文件 {r.swift}")
                continue
            if f"`{r.codex}`" not in table:
                problems.append(f"PORTING.md 缺少行 {r.codex}（运行 generate 刷新）")

    if problems:
        print(f"✗ harness_port check: {len(problems)} 个问题")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"✓ harness_port check 通过（{len(swift)} 个 Swift 文件，基线 {rev[:8]}）")
    return 0


# ---------------------------------------------------------------------------
# stats
# ---------------------------------------------------------------------------

def stats() -> None:
    rows = [r for r in build_rows() if r.status != "sage-addition"]
    total = len(rows)
    done = sum(1 for r in rows if r.status in ("faithful", "adapted", "partial"))
    stub = sum(1 for r in rows if r.status == "stub")
    print(f"范围内文件 {total}：已移植 {done}（{done * 100 // max(total, 1)}%），stub {stub}，"
          f"未开始 {sum(1 for r in rows if r.status == 'not-started')}，"
          f"excluded/deferred {sum(1 for r in rows if r.status in ('excluded', 'deferred'))}")
    for phase in sorted({r.phase for r in rows if r.phase is not None}):
        rs = [r for r in rows if r.phase == phase]
        d = sum(1 for r in rs if r.status in ("faithful", "adapted", "partial"))
        loc = sum(r.lines for r in rs)
        print(f"  Phase {phase:>2}: {d:>3}/{len(rs):<3} 文件，{loc:,} 行 Rust")


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("generate", "check", "stats"):
        print(__doc__)
        return 2
    if not CODEX.is_dir():
        print(f"✗ 找不到 codex 仓库：{CODEX}")
        return 2
    mode = sys.argv[1]
    if mode == "generate":
        generate()
        return 0
    if mode == "check":
        return check()
    stats()
    return 0


if __name__ == "__main__":
    sys.exit(main())
