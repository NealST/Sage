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

    /// Observation tools can share a wave; shell / MCP / writes / todos stay serial.
    static func runsInParallel(_ toolName: String) -> Bool {
        guard ToolDefinition.observationToolNames.contains(toolName) else { return false }
        return toolName != ManageTodoListTool.name
            && toolName != ExploreSubagentTool.name
    }

    static func partition(_ steps: [AgentStep]) -> [ToolBatchWave] {
        var waves: [ToolBatchWave] = []
        var pending: [Int] = []

        func flushPending() {
            guard !pending.isEmpty else { return }
            if pending.count == 1 {
                waves.append(.serial(pending[0]))
            } else {
                waves.append(.parallel(pending))
            }
            pending = []
        }

        for index in steps.indices {
            if runsInParallel(steps[index].toolName) {
                pending.append(index)
            } else {
                flushPending()
                waves.append(.serial(index))
            }
        }
        flushPending()
        return waves
    }
}
