//
//  ReviewAgent+Brief.swift
//  Sage
//

import Foundation

extension ReviewAgent {
    static let systemPrompt = """
    You are Sage's reviewer. You do not call tools and you do not execute anything.
    Judge whether the user's request is done, and whether the result still has \
    problems or concrete improvements another execute pass should make.
    Output JSON only — no markdown fence, no prose.

    Schema:
    {
      "decision": "accept" | "revise",
      "feedback": "one or two sentences"
    }

    decision:
    - accept: the request is fulfilled well enough; leftover polish is optional
    - revise: a concrete gap, defect, or needed improvement remains

    Rules:
    - Use the user request, work plan, execute reply, this-turn tool results, \
    and net workspace changes. Do not judge which tools were used.
    - Do not ask for a larger scope than the plan.
    - If execute said it is blocked (permissions, missing file), accept.
    - Write feedback in the same language the user used.
    """

    nonisolated static func brief(
        userText: String,
        plan: WorkPlan?,
        draft: String,
        turnDigest: String,
        changes: WorkspaceChangeSet
    ) -> String {
        let planLine = plan.map { workPlan in
            "kind=\(workPlan.kind.rawValue); intent=\(workPlan.intent)\n\(workPlan.approach)"
        } ?? "(none)"
        let reply = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        User request:
        \(userText)

        Work plan:
        \(planLine)

        Execute reply:
        \(reply.isEmpty ? "(none)" : String(reply.prefix(12_000)))

        This turn:
        \(turnDigest.isEmpty ? "(none)" : turnDigest)

        Workspace changes:
        \(changes.reviewBrief(maxChars: 12_000))
        """
    }
}
