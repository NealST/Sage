//
//  mod.swift
//  CodexUtils
//
//  Port of codex-rs/core/src/utils/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Upstream is pure `mod` declarations (`json`, `path_utils`); module
//  structure is SPM target layout in Swift, so this file only preserves the
//  1:1 file mapping (plan §5.1 R1/R3). core's own module does not exist yet,
//  so this file compiles into CodexUtils (plan §4.1 transitional note).
//

import Foundation
