//
//  stream_parser_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Upstream's `mod` + `pub use` re-exports are no-ops in Swift: all files of
//  this crate compile into the same `CodexUtils` module, so every public
//  symbol is already visible module-wide. This file preserves the 1:1
//  file mapping (plan §5.1 R1).
//
//  R4a: upstream `lib.rs` maps to `stream_parser_lib.swift` because
//  `utils/absolute-path/src/lib.swift` claimed the basename first (plan §5.1).
//

import Foundation
