//
//  lib.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Upstream is `mod` declarations plus a handful of `pub use` re-exports
//  (`AgentPath`, `SessionId`, `ThreadId`, `ToolName`, ...). All files of this
//  crate compile into the same `CodexProtocol` module, so every public symbol
//  is already visible module-wide and the re-exports are no-ops. This file
//  only preserves the 1:1 file mapping (plan §5.1 R2/R3).
//

import Foundation
