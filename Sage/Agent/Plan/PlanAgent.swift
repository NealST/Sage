//
//  PlanAgent.swift
//  Sage
//
//  Sub-agent: thread judgment, skill recall, written work plan, persist gate.
//  No tools, no execution, no SKILL.md writes.
//

import Foundation

nonisolated struct SkillPersistAdvice: Sendable, Equatable {
    var persist: Bool
}

@MainActor
final class PlanAgent {
    private let state: AgentSessionState
    private let modelGateway: AgentModelGateway

    init(state: AgentSessionState, modelGateway: AgentModelGateway) {
        self.state = state
        self.modelGateway = modelGateway
    }

    func propose(
        userText: String,
        skillAppendix: String,
        allowedSkillNames: [String]
    ) async throws -> WorkPlan {
        let raw = try await modelGateway.completeUnstreamed(
            system: Self.systemPrompt,
            user: Self.proposeUserPrompt(
                userText: userText,
                threadContext: threadContext(),
                skillAppendix: skillAppendix
            ),
            role: .plan
        )
        let allowed = Set(allowedSkillNames)
        let plan = Self.parse(raw) ?? Self.fallback(for: userText)
        return WorkPlan(
            id: plan.id,
            kind: plan.kind,
            intent: plan.intent,
            approach: plan.approach,
            sideEffects: plan.sideEffects,
            threadAdvice: plan.threadAdvice,
            threadLabel: plan.threadLabel,
            skillNames: plan.skillNames.filter { allowed.contains($0) }
        )
    }

    /// After Review accept. Does not write files — only whether extraction should run.
    func judgePersistence(task: TaskRecord) async -> Bool {
        do {
            try Task.checkCancellation()
            let raw = try await modelGateway.completeUnstreamed(
                system: Self.persistSystemPrompt,
                user: Self.persistUserPrompt(task: task),
                role: .plan
            )
            try Task.checkCancellation()
            return Self.parsePersist(raw)?.persist ?? false
        } catch is CancellationError {
            return false
        } catch {
            return false
        }
    }

    static let systemPrompt = """
    You are Sage's planner. You do not call tools and you do not execute anything.
    Read the user's request and output a work plan as JSON only — no markdown fence around the JSON, no extra prose.

    Schema:
    {
      "kind": "answer" | "observe" | "act",
      "intent": "one sentence: what the user wants",
      "approach": "markdown document",
      "side_effects": "what may change on the Mac, or null",
      "thread": "continue" | "offer_fresh",
      "thread_label": "short name of the current thread if offering, else null",
      "skills": ["exact catalog names to load, or []"]
    }

    kind:
    - answer: you can reply from conversation context; no need to touch the Mac
    - observe: need to read, list, or inspect; no lasting change
    - act: will create, edit, delete, run a command, change the clipboard, notify, or otherwise mutate

    approach is the written plan for solving this task — not a checklist of tool calls.
    Use markdown. Cover the considerations that matter, for example:
    - how you read the request and what “done” looks like
    - constraints, what to leave alone, and why
    - tradeoffs or the path you are choosing
    - risks or uncertainty
    Keep it short enough to confirm at a glance (about a half page, not an essay).
    Never write tool names or JSON arguments.

    - side_effects is required for act, null otherwise.
    - Write intent and approach in the same language the user used.

    thread:
    - continue unless the latest request is clearly a different goal from the current thread
    - offer_fresh never starts a new thread; it only suggests Start Fresh
    - Prefer continue on short follow-ups, untitled / first turns, and anything that could still belong here
    - thread_label is the existing thread's name (not the new topic)

    skills:
    - Only names listed under Available Skills
    - Empty if none clearly apply
    - Do not invent names
    """

    static let persistSystemPrompt = """
    You are Sage's planner deciding whether a finished task is worth saving as a skill.
    You do not write files. Output JSON only — no markdown fence, no prose.

    Schema:
    {
      "persist": true | false,
      "reason": "one short sentence"
    }

    persist true only when the work produced a reusable procedure someone would want again.
    Skip one-off answers, trivial lookups, failed or abandoned work, and things already covered by an existing skill.
    """

    static func fallback(for userText: String) -> WorkPlan {
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

    static func parse(_ raw: String?) -> WorkPlan? {
        guard let object = ModelJSON.object(from: raw) else { return nil }
        guard let kindRaw = object["kind"] as? String,
              let kind = WorkPlan.Kind(rawValue: kindRaw),
              let intent = (object["intent"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !intent.isEmpty
        else { return nil }

        let approach: String
        if let text = object["approach"] as? String {
            approach = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let items = object["approach"] as? [String] {
            approach = items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { "- \($0)" }
                .joined(separator: "\n")
        } else {
            approach = ""
        }

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
            skillNames: skillNames
        )
    }

    static func parsePersist(_ raw: String?) -> SkillPersistAdvice? {
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

    private func threadContext() -> String {
        guard let task = state.activeTask else { return "No current thread." }
        let label = TopicDriftDetector.threadLabel(
            topic: task.topic,
            abstract: task.abstract,
            summary: task.summary
        ) ?? "untitled / new"
        var lines = ["Title: \(label)"]
        if let abstract = task.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
           !abstract.isEmpty {
            lines.append("Intent: \(abstract)")
        }
        let dialogue = task.events.filter { $0.kind == .userInput || $0.kind == .assistantResponse }
        let prior = dialogue.dropLast(dialogue.last?.kind == .userInput ? 1 : 0).suffix(6)
        if !prior.isEmpty {
            lines.append("Recent:")
            for event in prior {
                let clipped = String(
                    event.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)
                )
                guard !clipped.isEmpty else { continue }
                switch event.kind {
                case .userInput:
                    lines.append("User: \(clipped)")
                case .assistantResponse:
                    lines.append("Assistant: \(clipped)")
                default:
                    break
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func proposeUserPrompt(
        userText: String,
        threadContext: String,
        skillAppendix: String
    ) -> String {
        let skills = skillAppendix.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        ## Current thread
        \(threadContext)

        \(skills.isEmpty ? "## Available skills\nnone" : skills)

        ## Latest request
        \(userText)
        """
    }

    private static func persistUserPrompt(task: TaskRecord) -> String {
        let topic = TopicDriftDetector.threadLabel(
            topic: task.topic,
            abstract: task.abstract,
            summary: task.summary
        ) ?? "untitled"
        return """
        Thread: \(topic)
        Transcript:
        \(TranscriptDigest.make(from: task.events))
        """
    }
}
