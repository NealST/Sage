//
//  function_tool.swift
//  Sage
//
//  Port of codex-rs/core/src/function_tool.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Upstream re-exports `codex_tools::FunctionCallError`. The tools crate is
//  not a separate Swift module yet, so the type lives in this CodexCore
//  file (also used by apply_patch.swift).
//

public enum FunctionCallError: Error, Equatable, CustomStringConvertible {
    case respondToModel(String)
    case fatal(String)

    public var description: String {
        switch self {
        case .respondToModel(let message):
            return message
        case .fatal(let message):
            return "Fatal error: \(message)"
        }
    }
}
