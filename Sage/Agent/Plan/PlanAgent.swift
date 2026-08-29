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
        var adapter = PlanStreamAdapter()
        let raw = try await modelGateway.streamCustom(
            system: Self.systemPrompt,
            user: Self.proposeUserPrompt(
                userText: userText,
                threadContext: threadContext(),
                skillAppendix: skillAppendix
            ),
            role: .plan
        ) { chunk in
            if let visible = adapter.ingest(chunk) {
                modelGateway.streaming.publish(visible)
            }
        }
        return adoptProposal(
            adapter.finish(),
            raw: raw,
            userText: userText,
            allowed: Set(allowedSkillNames)
        )
    }

    private func adoptProposal(
        _ outcome: PlanStreamAdapter.Outcome,
        raw: String,
        userText: String,
        allowed: Set<String>
    ) -> WorkPlan {
        if case .answer(let text) = outcome, let plan = Self.parsePlain(text) {
            modelGateway.streaming.flush(text)
            return plan
        }
        let plan = Self.parse(raw) ?? Self.fallback(for: userText)
        return WorkPlan(
            id: plan.id,
            kind: plan.kind,
            intent: plan.intent,
            approach: plan.approach,
            sideEffects: plan.sideEffects,
            threadAdvice: plan.threadAdvice,
            threadLabel: plan.threadLabel,
            skillNames: plan.skillNames.filter { allowed.contains($0) },
            reply: plan.reply
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
    You are Sage's planner. You do not call tools and you do not execute.

    Two output forms — pick one. The first token decides:

    1) Direct reply, when no Mac access is needed (greeting, joke, explanation, follow-up from context):
    Write the user-facing answer as markdown. No JSON, no preamble, no "kind".

    2) Work plan, when you must read or change the Mac:
    JSON only. First character is `{`. No markdown fence, no prose before the JSON.
    {
      "kind": "observe" | "act",
      "intent": "one sentence: what the user wants",
      "approach": "markdown plan",
      "side_effects": "what may change on the Mac, or null",
      "thread": "continue" | "offer_fresh",
      "thread_label": "short name of the current thread if offering, else null",
      "skills": ["exact catalog names to load, or []"]
    }

    Prefer (1) whenever tools are unnecessary. Do not invent an observe or act plan for chitchat.

    kind:
    - observe: read, list, or inspect; no lasting change. Mutating tools are rejected at runtime.
    - act: create, edit, delete, run a command, change the clipboard, notify, or otherwise mutate

    approach is the written plan — not a checklist of tool calls. Use markdown. Cover:
    - how you read the request and what “done” looks like
    - constraints, what to leave alone, and why
    - tradeoffs or the path you are choosing
    - risks or uncertainty
    Keep it short enough to confirm at a glance (about a half page).
    Never write tool names or JSON arguments.

    - side_effects is required for act, null otherwise.
    - Write the reply, intent, and approach in the same language the user used.

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
