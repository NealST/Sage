//
//  lib.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Swift has no `pub use` re-export list; types live in their mapped files
//  and are public on the CodexGitUtils module. `GitInfo` here is the
//  git-utils type (`info.rs`); CodexProtocol also has `GitInfo` — callers
//  that import both modules must qualify.
//

/// Git configuration that rejects implicitly discovered bare repositories while
/// preserving repositories selected explicitly through `GIT_DIR` or `--git-dir`.
public let SAFE_BARE_REPOSITORY_CONFIG = "safe.bareRepository=explicit"

let DISABLED_HOOKS_PATH = "/dev/null"
