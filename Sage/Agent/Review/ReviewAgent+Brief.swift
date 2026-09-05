//
//  ReviewAgent+Brief.swift
//  Sage
//

import Foundation

extension ReviewAgent {
    static let systemPrompt = """
    You are Sage's reviewer. You inspect the current world. You do not change it.
    You do not write files, run shell, compile, or test. Execute already did the work.
    Your job is gap-finding and quality assessment against the confirmed contract.

    Use the read-only tools to look at what exists now — files, folders, clipboard, \
    volume, frontmost app. If places to inspect are listed, start there. Still read \
    them yourself; the list is not evidence. Do not treat the draft reply as proof. \
    Do not invent a change log. If something cannot be observed (a notification already gone), \
    judge only from the plan and what you can still see. Do not assume it failed \
    just because you cannot replay the action.

    Output JSON only when you have looked enough — no markdown fence, no prose.

    Schema:
    {
      "must_fix": "one or two sentences, or empty",
      "optional": "one or two sentences, or empty"
    }

    must_fix: missing work, holes, bugs, or a draft that contradicts what you observed. Empty if none.
    optional: real quality or experience improvements that are not required. Empty if none.

    Rules:
    - Stay inside the confirmed plan. Do not ask for a larger job.
    - Do not put prose or tone nits in either field.
    - Do not report compile or test failures; that is Execute's loop.
    - Write both fields in the same language the user used.
    """

    nonisolated static func brief(
        userText: String,
        workPlan: WorkPlan?,
        draft: String,
        sandbox: String,
        inspectPlaces: [String] = []
    ) -> String {
        let planLines: String
        if let workPlan {
            var lines = [
                "Confirmed plan:",
                "Intent: \(workPlan.intent)",
            ]
            if !workPlan.approach.isEmpty {
                lines.append("Approach: \(workPlan.approach)")
            }
            if let sideEffects = workPlan.sideEffects, !sideEffects.isEmpty {
                lines.append("Side effects: \(sideEffects)")
            }
            planLines = lines.joined(separator: "\n") + "\n\n"
        } else {
            planLines = ""
        }
        let reply = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftBlock = reply.isEmpty ? "" : "Draft reply:\n\(reply)\n\n"
        let placesBlock: String
        if inspectPlaces.isEmpty {
            placesBlock = ""
        } else {
            let lines = inspectPlaces.map { "- \($0)" }.joined(separator: "\n")
            placesBlock = """
            Places to inspect (look here first; read them yourself):
            \(lines)


            """
        }
        return """
        User request:
        \(userText)

        \(planLines)\(draftBlock)\(placesBlock)Sandbox:
        \(sandbox)

        Inspect the current Mac yourself with the read-only tools, then output the JSON verdict.
        """
    }
}
