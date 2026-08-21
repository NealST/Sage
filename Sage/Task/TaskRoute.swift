//
//  TaskRoute.swift
//  Sage
//
//  Single routing decision + continuity resolver (sticky current task).
//

import Foundation

nonisolated enum TaskRouteAction: Sendable, Equatable {
    case continueActive
    case beginNew
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
    ) -> Self {
        Self(
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
    ) -> Self {
        Self(
            action: .beginNew,
            relatedTaskIDs: [],
            confidence: confidence,
            reason: reason,
            userVisibleHint: userVisibleHint
        )
    }
}

/// Strategy seam for deterministic routing rules.
nonisolated protocol TaskRouting: Sendable {
    func route(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) -> TaskRoute
}

/// Continuity only: explicit fresh-start language, or keep the current task.
/// Topic drift is a UI offer (`TopicDriftDetector`), never a route.
@MainActor
final class CompositeTaskRouter {
    private let continuity: ContinuityTaskResolver

    init(continuity: ContinuityTaskResolver = ContinuityTaskResolver()) {
        self.continuity = continuity
    }

    func route(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) -> TaskRoute {
        let firstPass = continuity.route(input: input, workspace: workspace)
        guard case .continueActive = firstPass.action else {
            return firstPass
        }

        var continued = firstPass
        if continued.relatedTaskIDs.isEmpty {
            continued.relatedTaskIDs = workspace.activeTask?.relatedTaskIDs ?? []
        }
        return continued
    }
}
