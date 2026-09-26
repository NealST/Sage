//
//  user_goal.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/user_goal.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public enum ThreadGoalStatus: String, Codable, Equatable, Sendable {
    case active
    case completed
    case cancelled
}

public enum UserGoalUpdate: ContextualUserFragment, Equatable, Sendable {
    case set(objective: String?, status: ThreadGoalStatus?)
    case clear

    public static let omittedObjectiveKind = "user.goal.omitted"
    public static let maxObjectiveBytes = 700

    public var role: String { "user" }

    public var contentKind: ContentItemKind {
        switch self {
        case .set(let objective, _):
            if let objective, (try? JSONEncoder().encode(objective))?.count ?? 0 > Self.maxObjectiveBytes {
                return ContentItemKind(Self.omittedObjectiveKind)
            }
            return ContentItemKind("user.goal")
        case .clear:
            return ContentItemKind("user.goal")
        }
    }

    public var openMarker: String { "<codex_internal_context source=\"user_goal\">" }
    public var closeMarker: String { "</codex_internal_context>" }

    public var body: String {
        switch self {
        case .set(let objective, let status):
            var text = "\n"
            if let objective {
                if let data = try? JSONEncoder().encode(objective),
                   let encoded = String(data: data, encoding: .utf8),
                   encoded.utf8.count <= Self.maxObjectiveBytes {
                    text += "User set the goal: \(encoded)\n"
                } else {
                    text += "User set the goal: [objective omitted; exceeds the evidence limit].\n"
                }
            }
            if let status {
                text += "User set goal status: \"\(status.rawValue)\".\n"
            }
            return text
        case .clear:
            return "\nUser cleared the goal.\n"
        }
    }

    public static func messageText(_ item: ResponseItem) -> String? {
        guard case .message(_, let role, let content, _, let metadata) = item,
              role == "user",
              let kinds = metadata?.contentItemKinds,
              kinds.count == 1,
              let kind = kinds.first,
              kind.value == "user.goal" || kind.value == omittedObjectiveKind,
              content.count == 1,
              case .inputText(let text) = content[0]
        else { return nil }
        return text
    }
}
