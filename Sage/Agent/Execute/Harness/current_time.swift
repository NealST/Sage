//
//  current_time.swift
//  CodexCore
//
//  Port of codex-rs/core/src/current_time.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Host clock boundary. tokio::time::sleep becomes Task.sleep.
//  CurrentTimeSource lives here so CodexCore does not depend on the
//  Sage-app Config module.
//

import CodexProtocol
import Foundation

public enum CurrentTimeSource: String, Equatable, Sendable {
    case system
    case external
}

public enum CurrentTimeReminderDeliveryMode: String, Equatable, Sendable {
    case anyInference = "any_inference"
    case afterUserOrToolOutput = "after_user_or_tool_output"
}

public protocol TimeProvider: Sendable {
    func currentTime(threadId: ThreadId) async throws -> Date
    func sleep(threadId: ThreadId, duration: Duration) async throws
}

public struct SystemTimeProvider: TimeProvider {
    public init() {}

    public func currentTime(threadId: ThreadId) async throws -> Date {
        Date()
    }

    public func sleep(threadId: ThreadId, duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

public func resolveTimeProvider(
    clockSource: CurrentTimeSource,
    externalProvider: (any TimeProvider)?
) throws -> any TimeProvider {
    switch clockSource {
    case .system:
        return SystemTimeProvider()
    case .external:
        guard let externalProvider else {
            throw CodexErr.fatal(
                "features.current_time_reminder.clock_source is external, but no external current-time provider is available"
            )
        }
        return externalProvider
    }
}
