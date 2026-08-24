//
//  ReviewAgent.swift
//  Sage
//
//  Sub-agent: judge whether the work plan was fulfilled. No tools.
//

import Foundation

nonisolated struct ReviewVerdict: Sendable, Equatable {
    enum Decision: String, Sendable {
        case accept
        case revise
    }

    var decision: Decision
    /// Short note. For revise, this is what the execute agent should fix.
    var feedback: String
}

@MainActor
final class ReviewAgent {
    static let maxRevisions = 2

    private let state: AgentSessionState
    private let modelGateway: AgentModelGateway

    init(state: AgentSessionState, modelGateway: AgentModelGateway) {
        self.state = state
        self.modelGateway = modelGateway
    }

    func evaluate() async throws -> ReviewVerdict {
        let plan = state.activeTask?.workPlan
        let userText = state.events.last { $0.kind == .userInput }?
            .modelFacingContent(includeImagePixels: false) ?? ""
        let planLine = plan.map { workPlan in
            "kind=\(workPlan.kind.rawValue); intent=\(workPlan.intent)\n\(workPlan.approach)"
        } ?? "(none)"
        let brief = """
        User request:
        \(userText)

        Work plan:
        \(planLine)

        What happened:
        \(TranscriptDigest.make(from: state.events))
        """
        let raw = try await modelGateway.completeUnstreamed(
            system: Self.systemPrompt,
            user: brief,
            role: .review
        )
        return Self.parse(raw) ?? Self.fallbackAccept()
    }

    static let systemPrompt = """
    You are Sage's reviewer. You do not call tools and you do not execute anything.
    Compare the user's request and the work plan against what the execute agent actually did.
    Output JSON only — no markdown fence, no prose.

    Schema:
    {
      "decision": "accept" | "revise",
      "feedback": "one or two sentences"
    }

    decision:
    - accept: the intent is met well enough; leftover polish is optional
    - revise: a concrete gap remains that another execute pass can fix

    Rules:
    - Judge outcomes, not whether specific tools were used.
    - Do not ask for a larger scope than the plan.
    - If the execute agent already said it is blocked (permissions, missing file), accept and do not loop.
    - Write feedback in the same language the user used.
    """

    nonisolated static func parse(_ raw: String?) -> ReviewVerdict? {
        guard let object = ModelJSON.object(from: raw),
              let decisionRaw = object["decision"] as? String,
              let decision = ReviewVerdict.Decision(rawValue: decisionRaw)
        else { return nil }
        let feedback = (object["feedback"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ReviewVerdict(decision: decision, feedback: feedback)
    }

    nonisolated static func fallbackAccept() -> ReviewVerdict {
        ReviewVerdict(decision: .accept, feedback: "")
    }
}
