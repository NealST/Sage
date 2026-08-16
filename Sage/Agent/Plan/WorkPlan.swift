//
//  WorkPlan.swift
//  Sage
//
//  A problem-solving strategy. Not a list of tool calls.
//

import Foundation

/// Intent + written plan produced by the plan sub-agent. The user confirms this,
/// then the execution agent ReActs until the task is done.
nonisolated struct WorkPlan: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        /// Reply from context — no Mac changes.
        case answer
        /// Look around (read / list / search) — no lasting change.
        case observe
        /// Will change files, apps, clipboard, or the system.
        case act
    }

    /// Plan-model thread judgment. Never splits on its own.
    enum ThreadAdvice: String, Codable, Sendable {
        case continueThread = "continue"
        case offerFresh = "offer_fresh"
    }

    let id: UUID
    var kind: Kind
    /// One sentence: what the user wants.
    var intent: String
    /// Markdown plan: considerations, constraints, tradeoffs — not a tool checklist.
    var approach: String
    /// What may change on the Mac. Nil for answer / observe.
    var sideEffects: String?
    /// Soft Start Fresh offer. Confirmation peels the last user turn.
    var threadAdvice: ThreadAdvice
    /// Existing-thread name used in the drift chip.
    var threadLabel: String?
    /// Catalog names the plan model wants loaded before execute.
    var skillNames: [String]

    init(
        id: UUID = UUID(),
        kind: Kind,
        intent: String,
        approach: String,
        sideEffects: String? = nil,
        threadAdvice: ThreadAdvice = .continueThread,
        threadLabel: String? = nil,
        skillNames: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.approach = approach
        self.sideEffects = sideEffects?.nilIfEmpty
        self.threadAdvice = threadAdvice
        self.threadLabel = threadLabel?.nilIfEmpty
        self.skillNames = skillNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        intent = try container.decode(String.self, forKey: .intent)
        if let text = try? container.decode(String.self, forKey: .approach) {
            approach = text
        } else if let items = try? container.decode([String].self, forKey: .approach) {
            approach = items.map { "- \($0)" }.joined(separator: "\n")
        } else {
            approach = ""
        }
        sideEffects = try container.decodeIfPresent(String.self, forKey: .sideEffects)?.nilIfEmpty
        threadAdvice = (try? container.decode(ThreadAdvice.self, forKey: .threadAdvice)) ?? .continueThread
        threadLabel = try container.decodeIfPresent(String.self, forKey: .threadLabel)?.nilIfEmpty
        skillNames = (try? container.decode([String].self, forKey: .skillNames)) ?? []
    }

    var requiresConfirmation: Bool { kind == .act }

    /// Injected into the execution agent's system prompt after the plan is accepted.
    var promptAppendix: String {
        var lines = [
            "",
            "## Confirmed work plan",
            "Follow this plan. Use tools as needed. Do not ask the user to re-approve individual tools.",
            "Intent: \(intent)",
        ]
        if !approach.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Plan:")
            lines.append(approach)
        }
        if let sideEffects, !sideEffects.isEmpty {
            lines.append("Expected side effects: \(sideEffects)")
        }
        if !skillNames.isEmpty {
            lines.append("Recalled skills (already loaded): \(skillNames.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(intent, forKey: .intent)
        try container.encode(approach, forKey: .approach)
        try container.encodeIfPresent(sideEffects, forKey: .sideEffects)
        try container.encode(threadAdvice, forKey: .threadAdvice)
        try container.encodeIfPresent(threadLabel, forKey: .threadLabel)
        try container.encode(skillNames, forKey: .skillNames)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, intent, approach, sideEffects
        case threadAdvice, threadLabel, skillNames
    }
}
