//
//  path_utils.swift
//  CodexUtils
//
//  Port of codex-rs/core/src/utils/path_utils.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Upstream is `pub use codex_utils_path::*;` — a re-export of the
//  `utils/path-utils` crate. Both compile into the same `CodexUtils` module
//  here, so the re-export is a no-op and this file only preserves the 1:1
//  file mapping (plan §5.1 R1). core's own module does not exist yet
//  (plan §4.1 transitional note).
//

import Foundation
