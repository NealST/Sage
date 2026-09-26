//
//  lib.swift
//  CodexContextFragments
//
//  Port of codex-rs/context-fragments/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Upstream is `mod` declarations plus `pub use` re-exports. All files of
//  this crate compile into the same `CodexContextFragments` module, so the
//  re-exports are no-ops. This file preserves the 1:1 mapping (plan §5.1).
//

import Foundation
