//
//  TaskRoute.swift
//  Sage
//
//  Single routing decision + composite resolver (continuity → local model → heuristic).
//

import Foundation

nonisolated enum TaskRouteAction: Sendable, Equatable {
    case continueActive
    case beginNew
    case resumeTask(UUID)
}

/// Unified routing decision for submit.
nonisolated struct TaskRoute: Sendable, Equatable {
    var action: TaskRouteAction
    var relatedTaskIDs: [UUID]
    var confidence: Double
    var reason: String
    var userVisibleHint: String?

    var eventContext: EventContext {
        EventContext(
            relatedTaskIDs: relatedTaskIDs,
            confidence: confidence,
            reason: reason
        )
    }

    static func continueActive(
        relatedTaskIDs: [UUID] = [],
        confidence: Double = 1,
        reason: String,
        userVisibleHint: String? = nil
    ) -> TaskRoute {
        TaskRoute(
            action: .continueActive,
            relatedTaskIDs: relatedTaskIDs,
            confidence: confidence,
            reason: reason,
            userVisibleHint: userVisibleHint
        )
    }

    static func beginNew(
        confidence: Double = 1,
        reason: String,
        userVisibleHint: String? = nil
    ) -> TaskRoute {
        TaskRoute(
            action: .beginNew,
            relatedTaskIDs: [],
            confidence: confidence,
            reason: reason,
            userVisibleHint: userVisibleHint
        )
    }

    static func resume(
        _ id: UUID,
        relatedTaskIDs: [UUID] = [],
        confidence: Double,
        reason: String,
        userVisibleHint: String?
    ) -> TaskRoute {
        TaskRoute(
            action: .resumeTask(id),
            relatedTaskIDs: relatedTaskIDs,
            confidence: confidence,
            reason: reason,
            userVisibleHint: userVisibleHint
        )
    }
}

/// Strategy seam for deterministic rules, an on-device model, or a hybrid resolver.
nonisolated protocol TaskRouting: Sendable {
    func route(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) async -> TaskRoute
}

/// Continuity filter → local MLX router → heuristic fallback. Always returns a `TaskRoute`.
@MainActor
final class CompositeTaskRouter {
    private let continuity: ContinuityTaskResolver
    private let taskRouter: TaskRouter

    init(
        continuity: ContinuityTaskResolver = ContinuityTaskResolver(),
        taskRouter: TaskRouter = TaskRouter()
    ) {
        self.continuity = continuity
        self.taskRouter = taskRouter
    }

    func route(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) async -> TaskRoute {
        let firstPass = await continuity.route(input: input, workspace: workspace)
        guard case .continueActive = firstPass.action else {
            return firstPass
        }

        let catalog = TaskCatalog.build(
            from: workspace.recentSummaries,
            excluding: workspace.activeTaskID
        )
        let activeIsEmpty = workspace.activeTask?.events.isEmpty ?? true

        if catalog.entries.isEmpty && activeIsEmpty {
            return HeuristicTaskFallback.decide(input: input, workspace: workspace)
                ?? firstPass
        }

        let modelRoute = await taskRouter.route(
            input: input,
            currentTopic: workspace.activeTask?.topic
                ?? workspace.activeTask?.summary.map { String($0.prefix(20)) },
            catalog: catalog
        )

        switch modelRoute.action {
        case .continueActive:
            if modelRoute.confidence <= 0.5 {
                return HeuristicTaskFallback.decide(input: input, workspace: workspace)
                    ?? enrichContinue(modelRoute, workspace: workspace)
            }
            return enrichContinue(modelRoute, workspace: workspace)
        case .beginNew:
            return modelRoute
        case .resumeTask(let id):
            let hint = ContextHint.forResumedTask(
                topic: workspace.recentSummaries.first(where: { $0.id == id })?.topic,
                summary: workspace.recentSummaries.first(where: { $0.id == id })?.summary
            )
            return TaskRoute.resume(
                id,
                confidence: modelRoute.confidence,
                reason: modelRoute.reason,
                userVisibleHint: hint
            )
        }
    }

    private func enrichContinue(_ route: TaskRoute, workspace: TaskWorkspaceSnapshot) -> TaskRoute {
        var enriched = route
        if enriched.relatedTaskIDs.isEmpty {
            enriched.relatedTaskIDs = workspace.activeTask?.relatedTaskIDs ?? []
        }
        return enriched
    }
}
