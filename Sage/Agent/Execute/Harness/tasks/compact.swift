//
//  compact.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/compact.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Routes like Codex CompactTask: token-budget installs a fresh window,
//  otherwise `runAutoCompact` does remote V2 or a local fold. Occupancy
//  helpers stay here so Sage fold and the harness window share one
//  threshold and reset contract.
//

import CodexAsyncUtils
import CodexCore
import CodexProtocol
import Foundation

enum CompactTask {
    /// Auto-fold when occupancy reaches this, even if pins still fit.
    static let autoCompactThreshold = CompactTokenBudget.autoCompactThreshold

    enum Strategy: Equatable, Sendable {
        case tokenBudget
        case remoteV2
        case local
    }

    enum Outcome: Equatable, Sendable {
        case folded
        case skipped
        case failed(String)

        var notice: String? {
            switch self {
            case .folded:
                return nil

            case .skipped:
                return nil

            case .failed(let reason):
                return """
                Could not fold earlier turns (\(reason)). \
                The work plan and activated skills stayed in context; \
                older tool output may be missing.
                """
            }
        }
    }

    static func selectStrategy(tokenBudgetEnabled: Bool, remoteV2Available: Bool) -> Strategy {
        if tokenBudgetEnabled { return .tokenBudget }
        if remoteV2Available { return .remoteV2 }
        return .local
    }

    /// Codex `start_new_context_window`: bump the window id and drop prefill
    /// so the next sample is measured against a new token-budget window.
    @discardableResult
    static func resetWindow(_ window: inout AutoCompactWindow) -> (UInt64, AutoCompactWindowIds) {
        let advanced = window.advance()
        window.clearPrefill()
        return advanced
    }

    static func run(
        sess: Session,
        stepContext: StepContext,
        clientSession: inout ModelClientSession?,
        injection: InitialContextInjection
    ) async throws {
        switch selectStrategy(
            tokenBudgetEnabled: sess.features.enabled(.tokenBudget),
            remoteV2Available: clientSession != nil
        ) {
        case .tokenBudget:
            try await runInlineTokenBudgetCompact(
                sess: sess,
                stepContext: stepContext,
                injection: injection,
                trigger: .manual
            )
        case .remoteV2, .local:
            try await runAutoCompact(
                sess: sess,
                stepContext: stepContext,
                clientSession: &clientSession,
                injection: injection,
                trigger: .manual
            )
        }
    }

    /// Occupancy for UI and auto-fold. Prefer the last API prompt size when
    /// the provider reported one; otherwise Sage's CJK-aware estimator.
    static func occupancy(
        assembledTokens: Int,
        usableTokens: Int,
        reportedInputTokens: Int?
    ) -> Double {
        let usable = max(usableTokens, 1)
        if let reported = reportedInputTokens, reported > 0 {
            return min(Double(reported) / Double(usable), 1)
        }
        return min(Double(max(assembledTokens, 0)) / Double(usable), 1)
    }

    /// After a turn: last API prompt plus an estimate of events the model
    /// has not seen yet (tool results appended since that response).
    static func liveOccupancy(
        lastAPIInputTokens: Int,
        eventsAfterLastModel: [AgentEvent],
        usableTokens: Int
    ) -> Double {
        let extra = eventsAfterLastModel.reduce(0) { partial, event in
            partial + PromptBudget.estimatedTokenCount(of: event)
        }
        return occupancy(
            assembledTokens: extra,
            usableTokens: usableTokens,
            reportedInputTokens: lastAPIInputTokens + extra
        )
    }

    /// Work plan + runtime capability reminder must survive shrink.
    static func contractIsPreserved(system: String, layout: PromptLayout) -> Bool {
        kept(layout.workPlanAppendix, in: system)
            && kept(layout.capabilityReminder, in: system)
    }

    /// Tool results first (oldest first) so the compressor sees the evidence
    /// Codex would summarize; leftover budget keeps other events newest-first.
    static func selectFoldSlice(
        _ events: [AgentEvent],
        budget: PromptBudget
    ) -> [AgentEvent] {
        let timeline = events.filter { $0.kind != .systemInstruction && !$0.protected }
        let toolEvents = timeline.filter { event in
            event.kind == .toolResult || event.toolCalls != nil
        }
        let otherEvents = timeline.filter { event in
            event.kind != .toolResult && event.toolCalls == nil
        }

        var remaining = budget.usableTokens
        var selected: [AgentEvent] = []
        var seen = Set<UUID>()

        for event in toolEvents {
            let cost = PromptBudget.estimatedTokenCount(of: event)
            if cost > remaining {
                if selected.isEmpty {
                    selected.append(capForCompact(event, maxTokens: max(remaining, 1)))
                    remaining = 0
                }
                break
            }
            selected.append(event)
            seen.insert(event.id)
            remaining -= cost
        }

        if remaining > 0 {
            let extras = ContextBudget.fitEvents(
                otherEvents.filter { !seen.contains($0.id) },
                tokenBudget: remaining,
                forceIncludeNewest: false
            )
            selected.append(contentsOf: extras)
        }

        let order = Dictionary(uniqueKeysWithValues: timeline.enumerated().map { ($0.element.id, $0.offset) })
        return selected.sorted { lhs, rhs in
            (order[lhs.id] ?? .max) < (order[rhs.id] ?? .max)
        }
    }

    static let compactInstruction = """
    Fold the earlier turns into a working-memory snapshot. Do not call tools.
    Keep the user's confirmed work plan and activated skills exactly — do not \
    invent a new intent or drop a loaded skill.
    Prefer folding old tool output (tests, builds, git, search) over restating \
    recent user messages.
    First write a short <analysis> of the current state, then a <summary> block.
    Prefer a JSON object in <summary> with keys: overview, architecture, touchedFiles, \
    troubleshooting, progress, focus, recentActions, nextSteps.
    Each value is a concise paragraph. Omit unknown keys.
    If you cannot fill JSON, put a plain paragraph in <summary> instead.
    """

    private static func kept(_ slice: String, in system: String) -> Bool {
        let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || system.contains(trimmed)
    }

    private static func capForCompact(_ event: AgentEvent, maxTokens: Int) -> AgentEvent {
        ContextBudget.capToolResult(event, maxTokens: maxTokens)
    }
}

/// rust `CompactTask` as a SessionTask. Full remote V2 stays in `runTurn`.
final class CompactSessionTask: SessionTask, @unchecked Sendable {
    var kind: TaskKind { .compact }

    func run(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async throws -> String? {
        _ = input
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        _ = session.startNewContextWindow()
        session.sendEvent(context, .contextCompacted(ContextCompactedEvent()))
        return nil
    }
}
