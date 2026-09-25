//
//  decision.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/decision.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Allow < Prompt < Forbidden so `max()` over matched rules keeps the
//  strictest decision, matching upstream `Ord`.
//

public enum Decision: String, Codable, Equatable, Hashable, Sendable, Comparable {
    case allow
    case prompt
    case forbidden

    public static func parse(_ raw: String) throws -> Decision {
        switch raw {
        case "allow": return .allow
        case "prompt": return .prompt
        case "forbidden": return .forbidden
        default: throw ExecPolicyError.invalidDecision(raw)
        }
    }

    private var rank: Int {
        switch self {
        case .allow: return 0
        case .prompt: return 1
        case .forbidden: return 2
        }
    }

    public static func < (lhs: Decision, rhs: Decision) -> Bool {
        lhs.rank < rhs.rank
    }
}
