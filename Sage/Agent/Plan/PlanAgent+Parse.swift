//
//  PlanAgent+Parse.swift
//  Sage
//

import Foundation

enum PlanProposalError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "The work plan couldn't be read. Retry to try again."
    }
}

extension PlanAgent {
    /// Parse the JSON plan when present. Never invent an act card.
    nonisolated static func resolveProposal(
        _ outcome: PlanStreamAdapter.Outcome,
        raw: String
    ) throws -> ProposedWorkPlan {
        switch outcome {
        case .envelope(let envelope, let visible):
            guard let plan = parse(envelope) ?? parse(raw) else {
                throw PlanProposalError.unreadable
            }
            return ProposedWorkPlan(plan: plan, leadIn: visible)

        case .answer(let text):
            let source = PlanStreamAdapter.planJSONStart(in: text) != nil ? text : raw
            if let start = PlanStreamAdapter.planJSONStart(in: source),
               let plan = parse(source) {
                return ProposedWorkPlan(
                    plan: plan,
                    leadIn: String(source[..<start])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            if let plan = parsePlain(text) {
                return ProposedWorkPlan(plan: plan, leadIn: "")
            }
            throw PlanProposalError.unreadable
        }
    }

    nonisolated static func parsePlain(_ raw: String?) -> WorkPlan? {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, text.first != "{" else { return nil }
        let intent = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(120)) }
        guard let intent, !intent.isEmpty else { return nil }
        return WorkPlan(kind: .answer, intent: intent, approach: "", reply: text)
    }

    nonisolated static func parse(_ raw: String?) -> WorkPlan? {
        guard let object = ModelJSON.object(from: raw) else { return nil }
        guard let kindRaw = object["kind"] as? String,
              let kind = WorkPlan.Kind(rawValue: kindRaw),
              let intent = (object["intent"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !intent.isEmpty
        else { return nil }

        let approach = parseApproach(object)
        let reply = (object["reply"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        let sideEffects: String?
        if let value = object["side_effects"] as? String {
            sideEffects = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } else {
            sideEffects = nil
        }

        let threadAdvice = WorkPlan.ThreadAdvice(
            rawValue: (object["thread"] as? String) ?? "continue"
        ) ?? .continueThread
        let threadLabel = (object["thread_label"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let skillNames = ((object["skills"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return WorkPlan(
            kind: kind,
            intent: intent,
            approach: approach,
            sideEffects: kind == .act ? (sideEffects ?? "May change files or system state.") : nil,
            threadAdvice: threadAdvice,
            threadLabel: threadLabel,
            skillNames: skillNames,
            reply: reply
        )
    }

    nonisolated static func parsePersist(_ raw: String?) -> SkillPersistAdvice? {
        guard let object = ModelJSON.object(from: raw) else { return nil }
        if let persist = object["persist"] as? Bool {
            return SkillPersistAdvice(persist: persist)
        }
        if let persist = object["persist"] as? String {
            switch persist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return SkillPersistAdvice(persist: true)

            case "false", "no", "0":
                return SkillPersistAdvice(persist: false)

            default:
                return nil
            }
        }
        return nil
    }

    nonisolated private static func parseApproach(_ object: [String: Any]) -> String {
        if let text = object["approach"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let items = object["approach"] as? [String] {
            return items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { "- \($0)" }
                .joined(separator: "\n")
        }
        return ""
    }
}
