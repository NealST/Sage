//
//  ToolInvocationPipeline.swift
//  Sage
//
//  Thin adapter. Validate / timeout / dispatch live on `ToolOrchestrator`.
//

import Foundation

nonisolated enum ToolInvocationPipeline {
    @MainActor
    static func execute(_ request: ToolInvocationRequest) async throws -> String {
        try await ToolOrchestrator.execute(request)
    }

    @MainActor
    static func prepare(_ request: ToolInvocationRequest) async throws -> ToolInvocationRequest {
        try await ToolOrchestrator.prepare(request)
    }

    @MainActor
    static func dispatchTimed(_ request: ToolInvocationRequest) async throws -> String {
        try await ToolOrchestrator.dispatchTimed(request)
    }

    @MainActor
    static func withTimeout<T: Sendable>(
        name: String,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await ToolOrchestrator.withTimeout(name: name, operation: operation)
    }

    @MainActor
    static func validateForAuthorization(
        _ request: ToolInvocationRequest
    ) throws -> ToolDefinition {
        try ToolOrchestrator.validateForAuthorization(request)
    }

    static func timeoutDuration(for name: String) -> Duration {
        ToolOrchestrator.timeoutDuration(for: name)
    }
}
