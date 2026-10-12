#!/usr/bin/env python3
"""Rename leftover Codex identifiers, env vars, paths, and command names to Sage.

Keeps Apache attribution that cites `codex-rs/` and OpenAI wire-protocol strings.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_NAMES = {
    "PORTING.md",
    "EXECUTE_HARNESS_PORT_PLAN.md",
    "harness_port.py",
    "rebrand_and_strip_codex_product.py",
    "rebrand_remaining_codex_identifiers.py",
}
SKIP_PARTS = {".build", "DerivedData", ".git", "xcuserdata"}
TEXT_SUFFIXES = {".swift", ".md", ".py", ".json", ".pbxproj", ".plist", ".txt", ".sbpl"}

# Placeholders so later replacements do not rewrite external/protocol strings.
PROTECT = [
    ("https://chatgpt.com/backend-api/codex", "<<CHATGPT_CODEX_URL>>"),
    ("/backend-api/codex", "<<BACKEND_API_CODEX>>"),
    ("https://github.com/openai/codex", "<<GITHUB_OPENAI_CODEX>>"),
    ("https://chatgpt.com/codex/", "<<CHATGPT_CODEX_SETTINGS>>"),
    ("x-openai-internal-codex-responses-lite", "<<X_OPENAI_CODEX_LITE>>"),
    ("codex_rollout_budget_units", "<<CODEX_ROLLOUT_BUDGET>>"),
    ("codex/encryptedContent", "<<CODEX_ENC_CONTENT>>"),
    ("codex/imageDetail", "<<CODEX_IMAGE_DETAIL>>"),
    ("codex.response.metadata", "<<CODEX_RESPONSE_METADATA>>"),
    ("codex.rate_limits", "<<CODEX_RATE_LIMITS>>"),
    ("codex_output_schema", "<<CODEX_OUTPUT_SCHEMA>>"),
    ("codex_other", "<<CODEX_OTHER>>"),
    ("codex-rs/", "<<CODEX_RS_SLASH>>"),
    ("codex-rs", "<<CODEX_RS>>"),
    ("codex_client::", "<<CODEX_CLIENT>>"),
    ("codex_features::", "<<CODEX_FEATURES>>"),
    ("codex-mcp", "<<CODEX_MCP>>"),
    ("codex-file-system", "<<CODEX_FILE_SYSTEM>>"),
    ("codex-api", "<<CODEX_API_CRATE>>"),
    ("no codex counterpart", "<<NO_CODEX_COUNTERPART>>"),
]

# Longer tokens first.
RENAMES = [
    ("filterNonCodexAppsMcpToolsOnly", "filterNonSageAppsMcpToolsOnly"),
    ("filterCodexAppsMcpTools", "filterSageAppsMcpTools"),
    ("xCodexRoutingHintHeader", "xSageRoutingHintHeader"),
    ("xCodexTurnStateHeader", "xSageTurnStateHeader"),
    ("xCodexTurnMetadataHeader", "xSageTurnMetadataHeader"),
    ("xCodexParentThreadIdHeader", "xSageParentThreadIdHeader"),
    ("CodexTurnMetadataPayload", "SageTurnMetadataPayload"),
    ("codexResponsesHeaders", "sageResponsesHeaders"),
    ("codexOssBaseUrl", "sageOssBaseUrl"),
    ("codexPackagePathDir", "sagePackagePathDir"),
    ("codexCLIPackageBin", "sageCLIPackageBin"),
    ("CodexShellLookupError", "SageShellLookupError"),
    ("codexLinuxSandboxExe", "sageLinuxSandboxExe"),
    ("codexSelfExe", "sageSelfExe"),
    ("CodexConversation", "SageConversation"),
    ("codexErrorInfo", "sageErrorInfo"),
    ("codexRolloutBudgetUnits", "sageRolloutBudgetUnits"),
    ("codexEncryptedContentMetaKey", "sageEncryptedContentMetaKey"),
    ("codexImageDetailMetaKey", "sageImageDetailMetaKey"),
    ("CODEX_VERSION_ENV_VAR", "SAGE_VERSION_ENV_VAR"),
    ("CODEX_SANDBOX_NETWORK_DISABLED", "SAGE_SANDBOX_NETWORK_DISABLED"),
    ("CODEX_ESCALATE_SOCKET", "SAGE_ESCALATE_SOCKET"),
    ("CODEX_SANDBOX", "SAGE_SANDBOX"),
    ("CODEX_VERSION", "SAGE_VERSION"),
    ("testFindCodexHome", "testFindSageHome"),
    ("find_codex_home", "find_sage_home"),
    ("codex-project-roots://", "sage-project-roots://"),
    ("codex-package.json", "sage-package.json"),
    ("codex-resources", "sage-resources"),
    ("codex-git-apply-", "sage-git-apply-"),
    ("codex-linux-sandbox", "sage-linux-sandbox"),
    (".codex-system-skills.marker", ".sage-system-skills.marker"),
    (".codex-atomic-", ".sage-atomic-"),
    (".codex-plugin", ".sage-plugin"),
    ("codex-intersect-", "sage-intersect-"),
    ("missing-codex-home", "missing-sage-home"),
    ("codex-home.txt", "sage-home.txt"),
    ("/tmp/codex-home", "/tmp/sage-home"),
    ("com.sage.codex-auth", "com.sage.auth"),
    ("user.name=Codex", "user.name=Sage"),
    ("## My request for Codex:", "## My request for Sage:"),
    ("codex-env://", "sage-env://"),
    ("codex-env", "sage-env"),
    ("amazonBedrockMantleClientAgentValue = \"codex\"", 'amazonBedrockMantleClientAgentValue = "sage"'),
    ("~/.codex", "~/.sage"),
    ("/.codex", "/.sage"),
    ("`.codex`", "`.sage`"),
    ("`.git` / `.codex`", "`.git` / `.sage`"),
    ("Codex-internal", "Sage-internal"),
    ("Codex-generated", "Sage-generated"),
    ("inside the Codex", "inside the Sage"),
    ("running Codex.", "running Sage."),
    ("Codex gateway", "Sage gateway"),
    ("Codex thread", "Sage thread"),
    ("Codex state", "Sage state"),
    ("Codex ", "Sage "),
]


def rewrite_text(text: str) -> str:
    protected = text
    for src, token in PROTECT:
        protected = protected.replace(src, token)
    for old, new in RENAMES:
        protected = protected.replace(old, new)
    # Restore placeholders.
    for src, token in PROTECT:
        protected = protected.replace(token, src)
    return protected


def iter_files() -> list[Path]:
    roots = [
        ROOT / "Sage",
        ROOT / "SageTests",
        ROOT / "Sage.xcodeproj" / "project.pbxproj",
        ROOT / "scripts",
    ]
    files: list[Path] = []
    for root in roots:
        paths = [root] if root.is_file() else root.rglob("*")
        for path in paths:
            if not path.is_file():
                continue
            if path.name in SKIP_NAMES:
                continue
            if any(part in SKIP_PARTS for part in path.parts):
                continue
            if path.suffix not in TEXT_SUFFIXES and path.name != "Package.swift":
                continue
            files.append(path)
    return files


def main() -> None:
    changed = 0
    for path in iter_files():
        original = path.read_text(encoding="utf-8")
        updated = rewrite_text(original)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            print(f"rewrote {path.relative_to(ROOT)}")
            changed += 1
    print(f"done ({changed} files)")


if __name__ == "__main__":
    main()
