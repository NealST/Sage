//
//  handlers_mod.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Re-exports Phase 4 handlers. Multi-agent / plugin handlers stay in
//  Phase 9. parse_arguments matches the upstream JSON deny-unknown helper.
//  R4a: basename collision with tools/mod.swift.
//

import CodexCore
import Foundation

func parseArguments<T: Decodable>(_ arguments: String) throws -> T {
    try parseToolArguments(arguments)
}
