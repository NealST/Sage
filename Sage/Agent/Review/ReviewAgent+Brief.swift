//
//  ReviewAgent+Brief.swift
//  Sage
//

import Foundation

extension ReviewAgent {
    static let systemPrompt = """
    You are Sage's reviewer. You do not call tools and you do not execute anything.
    Judge whether this turn completed the user's request, and how well.
    Output JSON only — no markdown fence, no prose.

    Schema:
    {
      "decision": "accept" | "revise",
      "feedback": "one or two sentences"
    }

    decision:
    - accept: the request is fulfilled well enough; leftover polish is optional
    - revise: a concrete gap or quality problem remains

    Rules:
    - Use only the user request and the net workspace changes.
    - Do not ask for a larger scope than the request.
    - If nothing changed and the request needed workspace work, revise.
    - Write feedback in the same language the user used.
    """

    nonisolated static func brief(
        userText: String,
        changes: WorkspaceChangeSet
    ) -> String {
        """
        User request:
        \(userText)

        Workspace changes:
        \(changes.reviewBrief(maxChars: 12_000))
        """
    }
}
