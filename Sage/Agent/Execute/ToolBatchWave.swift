//
//  ToolBatchWave.swift
//  Sage
//
//  Splits one tool batch into parallel observation waves and serial mutating steps.
//

import Foundation

/// One scheduling unit inside a tool batch.
nonisolated enum ToolBatchWave: Equatable, Sendable {
    /// Independent observation tools — may run concurrently.
    case parallel([Int])
    /// Mutating or stateful tool — runs alone, in order.
    case serial(Int)

    /// Observation tools can share a wave; patch / shell / MCP / todo / Mac mutations stay serial.
    static func runsInParallel(_ toolName: String) -> Bool {
        ParallelToolRuntime.supportsParallel(toolName)
    }

    static func partition(_ steps: [AgentStep]) -> [Self] {
        ParallelToolRuntime.partition(steps.map(\.toolName))
    }
}
