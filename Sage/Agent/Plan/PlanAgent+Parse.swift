//
//  PlanAgent+Parse.swift
//  Sage
//

import Foundation

extension PlanAgent {
    nonisolated static func fallback(for userText: String) -> WorkPlan {
        WorkPlan(
            kind: .act,
            intent: String(userText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
            approach: """
            ## 理解
            按用户这句话完成最小必要改动。

            ## 约束
            不扩大范围，不改无关文件。

            ## 路径
            先看清现状，再做最小修改。
            """,
            sideEffects: "May read or change files in the current workspace."
        )
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
