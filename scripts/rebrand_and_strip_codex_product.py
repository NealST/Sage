#!/usr/bin/env python3
"""Delete Codex product-layer ports and rebrand remaining identifiers Codex→Sage.

Keeps Apache attribution lines that cite `codex-rs/` as the upstream source.
Does not touch the sibling `codex/` git checkout.
"""

from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "Sage" / "Agent" / "Execute" / "Harness"
SAGE = ROOT / "Sage"
TESTS = ROOT / "SageTests"

# Directories / files that are Codex product, not agent runtime.
DELETE_PATHS = [
    HARNESS / "plugins",
    HARNESS / "apps",
    HARNESS / "tools" / "code_mode",
    HARNESS / "utils" / "plugins",
    HARNESS / "otel",
    HARNESS / "state" / "src",
    HARNESS / "thread-store" / "src" / "local",
    HARNESS / "Tests" / "Phase10OtelTests",
    HARNESS / "connectors.swift",
    HARNESS / "cyber_access_program.swift",
    HARNESS / "environment_selection.swift",
    HARNESS / "otel_init.swift",
    HARNESS / "attestation.swift",
    HARNESS / "installation_id.swift",
    HARNESS / "feedback_config.swift",
    HARNESS / "mcp_openai_file.swift",
    HARNESS / "session" / "plugin_selection.swift",
    HARNESS / "session" / "code_mode_warning.swift",
    HARNESS / "tools" / "handlers" / "request_plugin_install.swift",
    HARNESS / "tools" / "handlers" / "request_plugin_install_spec.swift",
    HARNESS / "tools" / "handlers" / "list_available_plugins_to_install.swift",
    HARNESS / "tools" / "handlers" / "list_available_plugins_to_install_spec.swift",
    HARNESS / "tools" / "handlers" / "wait_for_environment.swift",
    HARNESS / "model-provider-info" / "src" / "gateway_oauth.swift",
    HARNESS / "context" / "available_plugins_instructions.swift",
    HARNESS / "context" / "plugin_instructions.swift",
    HARNESS / "context" / "recommended_plugins_instructions.swift",
    HARNESS / "context" / "apps_instructions.swift",
    HARNESS / "context" / "environments_instructions.swift",
    HARNESS / "context" / "world_state" / "plugins_instructions.swift",
    HARNESS / "context" / "world_state" / "world_state_apps_instructions.swift",
    HARNESS / "context" / "world_state" / "world_state_environments_instructions.swift",
    HARNESS / "context" / "world_state" / "realtime.swift",
]

# Longer tokens first so prefixes do not double-replace.
RENAMES = [
    ("CodexContextFragments", "SageContextFragments"),
    ("CodexTerminalDetection", "SageTerminalDetection"),
    ("CodexModelProviderInfo", "SageModelProviderInfo"),
    ("CodexNetworkProxy", "SageNetworkProxy"),
    ("CodexShellCommand", "SageShellCommand"),
    ("CodexThreadStore", "SageThreadStore"),
    ("CodexAsyncUtils", "SageAsyncUtils"),
    ("CodexAgentRoles", "SageAgentRoles"),
    ("CodexExecPolicy", "SageExecPolicy"),
    ("CodexSandboxing", "SageSandboxing"),
    ("CodexGitUtils", "SageGitUtils"),
    ("CodexProtocol", "SageProtocol"),
    ("CodexHistory", "SageHistory"),
    ("CodexRollout", "SageRollout"),
    ("CodexHooks", "SageHooks"),
    ("CodexSkills", "SageSkills"),
    ("CodexState", "SageState"),
    ("CodexOtel", "SageOtel"),
    ("CodexCore", "SageCore"),
    ("CodexUtils", "SageUtils"),
    ("CodexAPI", "SageAPI"),
    ("CodexThread", "SageThread"),
    ("CodexDelegate", "SageDelegate"),
    ("CodexHarnessMetadata", "SageHarnessMetadata"),
    ("CodexErrorDetails", "SageErrorDetails"),
    ("CodexErrorInfo", "SageErrorInfo"),
    ("CodexResult", "SageResult"),
    ("CodexErr", "SageErr"),
    ("xCodexInstallationIdHeader", "xSageInstallationIdHeader"),
    ("codexProxyGitSshCommandMarker", "sageProxyGitSshCommandMarker"),
    ("codexHome", "sageHome"),
    ("CODEX_NETWORK_PROXY", "SAGE_NETWORK_PROXY"),
    ("CODEX_PROXY_GIT_SSH_COMMAND", "SAGE_PROXY_GIT_SSH_COMMAND"),
    ("CODEX_SQLITE_HOME", "SAGE_SQLITE_HOME"),
    ("CODEX_APPS_MCP_SERVER_NAME", "SAGE_APPS_MCP_SERVER_NAME"),
    ("MCP_TOOL_CODEX_APPS_META_KEY", "MCP_TOOL_SAGE_APPS_META_KEY"),
    ("x-codex-installation-id", "x-sage-installation-id"),
    ("codex_error_info", "sage_error_info"),
    ("codex_thread", "sage_thread"),
    ("codex_delegate", "sage_delegate"),
    ("codex-path", "sage-path"),
    ("codex-api", "sage-api"),
    ("codex_apps", "sage_apps"),
    ("ExecuteHarnessAttach", "ExecuteHarnessAttach"),  # no-op sentinel
]

PROTECT_SUBSTRINGS = (
    "Port of codex-rs",
    "codex-rs/",
    "Upstream revision",
    "apache-2.0",
    "Apache-2.0",
)

TEXT_SUFFIXES = {
    ".swift",
    ".md",
    ".py",
    ".json",
    ".pbxproj",
    ".plist",
    ".txt",
    ".sbpl",
}


def should_protect_line(line: str) -> bool:
    lower = line.lower()
    return any(token.lower() in lower for token in PROTECT_SUBSTRINGS)


def replace_identifiers(text: str) -> str:
    out_lines = []
    for line in text.splitlines(keepends=True):
        if should_protect_line(line):
            out_lines.append(line)
            continue
        new = line
        for old, new_tok in RENAMES:
            if old == new_tok:
                continue
            new = new.replace(old, new_tok)
        # Remaining standalone Codex/codex tokens in identifiers and strings.
        # Do not touch protected attribution lines (already skipped).
        new = new.replace("Codex ", "Sage ")
        new = new.replace("Codex'", "Sage'")
        new = new.replace('"Codex', '"Sage')
        new = new.replace("'Codex", "'Sage")
        out_lines.append(new)
    return "".join(out_lines)


def delete_product_paths() -> None:
    for path in DELETE_PATHS:
        if not path.exists():
            print(f"skip missing {path}")
            continue
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
        print(f"deleted {path.relative_to(ROOT)}")


def write_sqlite_config() -> None:
    dest = HARNESS / "rollout" / "src" / "sqlite_config.swift"
    dest.write_text(
        """
//
//  sqlite_config.swift
//  SageRollout
//
//  Sage addition (no codex counterpart as a standalone file).
//  Path helpers for rollout JSONL; Codex state-db product files were removed.
//

import Foundation

public struct SqliteConfig: Equatable, Sendable {
    public var sqliteHome: String

    public init(sqliteHome: String = "") {
        self.sqliteHome = sqliteHome
    }

    public static func fromSqliteHome(_ sqliteHome: String) -> SqliteConfig {
        SqliteConfig(sqliteHome: sqliteHome)
    }

    public static func newForTesting(_ sqliteHome: String) -> SqliteConfig {
        fromSqliteHome(sqliteHome)
    }

    public var home: String { sqliteHome }
}
""".lstrip()
    )
    helper = HARNESS / "rollout" / "src" / "guardian_source.swift"
    helper.write_text(
        """
//
//  guardian_source.swift
//  SageRollout
//
//  Sage addition. Isolated from the removed Codex state crate.
//

import CodexProtocol

public let GUARDIAN_THREAD_PREVIEW = "Approval review"

public func isGuardianReviewSource(_ source: SessionSource) -> Bool {
    if case .subAgent(.other(let name)) = source {
        return name == "guardian"
    }
    return false
}
""".lstrip()
    )


def rewrite_text_files() -> None:
    roots = [SAGE, TESTS, ROOT / "Sage.xcodeproj" / "project.pbxproj"]
    skip_parts = {".build", "DerivedData", ".git", "xcuserdata"}
    skip_names = {"PORTING.md", "EXECUTE_HARNESS_PORT_PLAN.md", "harness_port.py"}
    for root in roots:
        paths = [root] if root.is_file() else root.rglob("*")
        for path in paths:
            if not path.is_file():
                continue
            if path.name in skip_names:
                continue
            if any(part in skip_parts for part in path.parts):
                continue
            if path.suffix not in TEXT_SUFFIXES and path.name != "Package.swift":
                continue
            original = path.read_text(encoding="utf-8")
            updated = replace_identifiers(original)
            if updated != original:
                path.write_text(updated, encoding="utf-8")
                print(f"rewrote {path.relative_to(ROOT)}")


def rename_paths() -> None:
    mapping = [
        (HARNESS / "codex_thread.swift", HARNESS / "sage_thread.swift"),
        (HARNESS / "codex_delegate.swift", HARNESS / "sage_delegate.swift"),
        (HARNESS / "protocol" / "src" / "codex_error_info.swift", HARNESS / "protocol" / "src" / "sage_error_info.swift"),
        (HARNESS / "codex-api", HARNESS / "sage-api"),
    ]
    for src, dst in mapping:
        if src.exists() and not dst.exists():
            src.rename(dst)
            print(f"renamed {src.relative_to(ROOT)} -> {dst.relative_to(ROOT)}")


def strip_package_sources() -> None:
    package = HARNESS / "Package.swift"
    text = package.read_text(encoding="utf-8")
    drop_source_lines = [
        '"attestation.swift",',
        '"installation_id.swift",',
        '"feedback_config.swift",',
        '"mcp_openai_file.swift",',
        '"otel_init.swift",',
        '"apps",',
        '"connectors.swift",',
        '"cyber_access_program.swift",',
        '"plugins",',
        '"environment_selection.swift",',
        '"codex_thread.swift",',
        '"codex_delegate.swift",',
        '"sage_thread.swift",',  # re-add after
        '"sage_delegate.swift",',
    ]
    for line in drop_source_lines:
        text = text.replace(f'                {line}\n', "")
    text = text.replace(
        '"thread_manager",\n',
        '"thread_manager",\n                "sage_thread.swift",\n                "sage_delegate.swift",\n',
    )
    # If sage_thread was not inserted because thread_manager line already had it, leave as-is.
    if '"sage_thread.swift"' not in text:
        text = text.replace(
            '"thread_manager.swift",\n',
            '"thread_manager.swift",\n                "sage_thread.swift",\n',
        )
    if '"sage_delegate.swift"' not in text:
        text = text.replace(
            '"session/turn_input.swift",\n',
            '"session/turn_input.swift",\n                "sage_delegate.swift",\n',
        )
    package.write_text(text, encoding="utf-8")


def main() -> None:
    delete_product_paths()
    write_sqlite_config()
    rewrite_text_files()
    rename_paths()
    strip_package_sources()
    print("done")


if __name__ == "__main__":
    main()
