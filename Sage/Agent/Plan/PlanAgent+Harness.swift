//
//  PlanAgent+Harness.swift
//  Sage
//
//  The plan turn is one harness runTurn (M2): the planner samples with a
//  read-only tool allowlist, visible prose streams through the pump with
//  the work-plan card reserved while JSON is in flight, and the turn's
//  final assistant message feeds the unchanged PlanStreamAdapter /
//  resolveProposal pipeline. Prompt assembly and parsing stay in
//  PlanAgent.swift.
//

import Foundation

extension PlanAgent {
    /// D2's plan read-only set. `view_image` is reserved here but not yet
    /// model-visible: the harness output→image conversion is porting debt
    /// (view_image.swift, Phase 5–6), and advertising it would feed the
    /// model a base64 wall. It appears once that lands.
    static let planToolNames: Set<String> = [
        "list_directory",
        "read_text_file",
        "search_files",
        "view_image",
    ]

    func propose(
        userText: String,
        skillAppendix: String,
        allowedSkillNames: [String]
    ) async throws -> ProposedWorkPlan {
        let buffer = PlanTextStreamBuffer(streaming: modelGateway.streaming)
        phaseRunner.onSampleStart = { [buffer] in
            buffer.beginSample()
        }
        phaseRunner.onTextDelta = { [buffer] delta in
            buffer.ingestText(delta)
        }
        phaseRunner.onThinkingDelta = { [buffer] delta in
            buffer.ingestThinking(delta)
        }
        defer {
            phaseRunner.onSampleStart = nil
            phaseRunner.onTextDelta = nil
            phaseRunner.onThinkingDelta = nil
        }
        // No skill host means plan tools cannot execute; keep the turn
        // text-only, mirroring Review's degradation.
        let canInspect = !planToolDefinitions().isEmpty && skillHost != nil
        let finalMessage = try await phaseRunner.runTurn(
            profile: PhaseProfile(
                modelRole: .plan,
                systemPrompt: Self.systemPrompt,
                tools: modelGateway.availableToolDefinitions(),
                toolAllowlist: canInspect ? Self.planToolNames : []
            ),
            userText: Self.proposeUserPrompt(
                userText: userText,
                threadContext: threadContext(),
                skillAppendix: skillAppendix
            )
        )
        // The turn's final message is the authoritative output; the
        // streamed accumulation only covers turns whose last sample had no
        // text of its own.
        let streamedOutcome = buffer.finish()
        let outcome = Self.outcome(fromFinalMessage: finalMessage) ?? streamedOutcome
        return try adoptProposal(outcome, raw: finalMessage, allowed: Set(allowedSkillNames))
    }

    static func outcome(fromFinalMessage text: String) -> PlanStreamAdapter.Outcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var adapter = PlanStreamAdapter()
        _ = adapter.ingest(trimmed)
        return adapter.finish()
    }

    func planToolDefinitions() -> [ToolDefinition] {
        modelGateway.tools.definitions.filter { Self.planToolNames.contains($0.name) }
    }

    func invokePlanTool(_ call: ToolCallProposal) async throws -> String {
        // App-layer fallback: the registry allowlist gate rejects out-of-set
        // calls before this seam, so this only fires on direct dispatch.
        guard Self.planToolNames.contains(call.name) else {
            return "ERROR: Plan cannot call '\(call.name)'."
        }
        guard let skillHost else {
            return "ERROR: Plan inspect tools are unavailable."
        }
        do {
            var invocation = ToolInvocationRequest(
                name: call.name,
                argumentsJSON: call.argumentsJSON,
                tools: modelGateway.tools,
                mcp: nil,
                pathGuardPolicy: state.pathGuardPolicy,
                activatedSkillNames: state.activatedSkillNames,
                enabledSkills: skillHost.enabledSkills,
                skillHost: skillHost,
                workPlanKind: .observe,
                modelSettings: nil
            ).resolvingAuthorization()
            invocation.authorizationEvidence = skillHost.inheritedAuthorizationEvidence(
                name: call.name,
                argumentsJSON: call.argumentsJSON
            )
            return try await ToolOrchestrator.execute(invocation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }
}

/// Bridges harness text deltas to StreamingTextPump exactly as the old
/// `streamCustom` onText did: prose streams live, JSON reserves the
/// work-plan card, thinking accumulates and republishes.
@MainActor
private final class PlanTextStreamBuffer {
    private var adapter = PlanStreamAdapter()
    private var thinkingChunks: [String] = []
    private let streaming: StreamingTextPump

    init(streaming: StreamingTextPump) {
        self.streaming = streaming
    }

    /// A tool-follow-up round replaces the previous round's message: reset
    /// per-message state so round two's prose does not concatenate with
    /// round one's.
    func beginSample() {
        adapter = PlanStreamAdapter()
        thinkingChunks = []
    }

    func ingestText(_ delta: String) {
        if let visible = adapter.ingest(delta) {
            streaming.publish(visible)
        }
        streaming.setReservingWorkPlan(adapter.isReservingWorkPlan)
    }

    func ingestThinking(_ delta: String) {
        thinkingChunks.append(delta)
        streaming.publishThinking(thinkingChunks.joined())
    }

    func finish() -> PlanStreamAdapter.Outcome {
        if !thinkingChunks.isEmpty {
            streaming.flushThinking(thinkingChunks.joined())
        }
        return adapter.finish()
    }
}
