//
//  session_startup_prewarm.swift
//  SageCore
//
//  Port of codex-rs/core/src/session_startup_prewarm.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Handle / resolution / consume match upstream. `schedule_startup_prewarm`
//  still waits on Session + websocket `ModelClientSession.prewarmWebsocket`
//  (Phase 6 deferred transport). Auth-only prewarm is a no-op hook.
//  Upstream moved this file out of `session/`.
//

import SageAsyncUtils
import SageProtocol
import Foundation

let STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC = "sage.startup_prewarm.age_at_first_turn"
let STARTUP_PREWARM_DURATION_METRIC = "sage.startup_prewarm.duration"

/// No-op stand-in after the OTEL product crate was removed.
public struct SessionTelemetry: Sendable {
    public var conversationId: ThreadId
    public var model: String
    public var slug: String
    public var originator: String
    public var logUserPrompts: Bool
    public var terminalType: String
    public var sessionSource: SessionSource

    public init(
        conversationId: ThreadId,
        model: String,
        slug: String,
        originator: String,
        logUserPrompts: Bool,
        terminalType: String,
        sessionSource: SessionSource
    ) {
        self.conversationId = conversationId
        self.model = model
        self.slug = slug
        self.originator = originator
        self.logUserPrompts = logUserPrompts
        self.terminalType = terminalType
        self.sessionSource = sessionSource
    }

    public func recordStartupPhase(phase: String, duration: Duration, status: String) {
        _ = (phase, duration, status)
    }

    public func recordDuration(_ name: String, duration: Duration, tags: [(String, String)]) {
        _ = (name, duration, tags)
    }
}

public struct SessionStartupPrewarmHandle: Sendable {
    public var startedAt: ContinuousClock.Instant
    public var timeout: Duration
    public var task: Task<Result<ModelClientSession, Error>, Never>?

    public init(
        startedAt: ContinuousClock.Instant = ContinuousClock.now,
        timeout: Duration,
        task: Task<Result<ModelClientSession, Error>, Never>? = nil
    ) {
        self.startedAt = startedAt
        self.timeout = timeout
        self.task = task
    }

    public func abort() {
        task?.cancel()
    }

    public func resolve(
        sessionTelemetry: SessionTelemetry,
        cancellationToken: CancellationToken
    ) async -> SessionStartupPrewarmResolution {
        let resolveStartedAt = ContinuousClock.now
        let ageAtFirstTurn = resolveStartedAt - startedAt
        let remaining = max(.zero, timeout - ageAtFirstTurn)

        let resolution: SessionStartupPrewarmResolution
        if let task, task.isCancelled {
            resolution = .cancelled
        } else if let task {
            resolution = await Self.raceResolve(
                task: task,
                remaining: remaining,
                cancellationToken: cancellationToken,
                startedAt: startedAt
            )
        } else {
            resolution = .unavailable(status: "not_scheduled", prewarmDuration: nil)
        }

        let status = resolution.statusTag
        sessionTelemetry.recordStartupPhase(
            phase: "startup_prewarm_resolve",
            duration: ContinuousClock.now - resolveStartedAt,
            status: status
        )

        switch resolution {
        case .cancelled:
            sessionTelemetry.recordDuration(
                STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC,
                duration: ageAtFirstTurn,
                tags: [("status", "cancelled")]
            )
            sessionTelemetry.recordDuration(
                STARTUP_PREWARM_DURATION_METRIC,
                duration: ContinuousClock.now - startedAt,
                tags: [("status", "cancelled")]
            )
            return .cancelled
        case .ready:
            sessionTelemetry.recordDuration(
                STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC,
                duration: ageAtFirstTurn,
                tags: [("status", "consumed")]
            )
            return resolution
        case .unavailable(let failStatus, let prewarmDuration):
            sessionTelemetry.recordDuration(
                STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC,
                duration: ageAtFirstTurn,
                tags: [("status", failStatus)]
            )
            if let prewarmDuration {
                sessionTelemetry.recordDuration(
                    STARTUP_PREWARM_DURATION_METRIC,
                    duration: prewarmDuration,
                    tags: [("status", failStatus)]
                )
            }
            return resolution
        }
    }

    private static func raceResolve(
        task: Task<Result<ModelClientSession, Error>, Never>,
        remaining: Duration,
        cancellationToken: CancellationToken,
        startedAt: ContinuousClock.Instant
    ) async -> SessionStartupPrewarmResolution {
        await withTaskGroup(of: SessionStartupPrewarmResolution?.self) { group in
            group.addTask {
                let result = await task.value
                return resolutionFromJoinResult(result, startedAt: startedAt)
            }
            group.addTask {
                try? await Task.sleep(for: remaining)
                return .unavailable(
                    status: "timed_out",
                    prewarmDuration: ContinuousClock.now - startedAt)
            }
            group.addTask {
                await cancellationToken.waitForCancellation()
                return .cancelled
            }
            var first: SessionStartupPrewarmResolution?
            while let next = await group.next() {
                if let next {
                    first = next
                    group.cancelAll()
                    break
                }
            }
            return first ?? .unavailable(status: "join_failed", prewarmDuration: ContinuousClock.now - startedAt)
        }
    }

    static func resolutionFromJoinResult(
        _ result: Result<ModelClientSession, Error>,
        startedAt: ContinuousClock.Instant
    ) -> SessionStartupPrewarmResolution {
        switch result {
        case .success(let session):
            return .ready(session)
        case .failure:
            return .unavailable(status: "failed", prewarmDuration: nil)
        }
    }
}

public enum SessionStartupPrewarmResolution: Sendable {
    case cancelled
    case ready(ModelClientSession)
    case unavailable(status: String, prewarmDuration: Duration?)

    var statusTag: String {
        switch self {
        case .cancelled: "cancelled"
        case .ready: "ready"
        case .unavailable(let status, _): status
        }
    }
}

public func consumeStartupPrewarmForRegularTurn(
    _ handle: SessionStartupPrewarmHandle?,
    sessionTelemetry: SessionTelemetry,
    cancellationToken: CancellationToken
) async -> SessionStartupPrewarmResolution {
    guard let handle else {
        return .unavailable(status: "not_scheduled", prewarmDuration: nil)
    }
    return await handle.resolve(
        sessionTelemetry: sessionTelemetry,
        cancellationToken: cancellationToken
    )
}
