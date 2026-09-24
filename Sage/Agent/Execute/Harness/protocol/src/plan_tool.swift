//
//  plan_tool.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/plan_tool.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Types for the TODO tool arguments matching codex-vscode/todo-mcp.
//  `schemars`/`ts_rs` derives carry no runtime semantics and are not ported.
//

import Foundation

/// serde `rename_all = "snake_case"`.
public enum StepStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}

/// serde `deny_unknown_fields`.
public struct PlanItemArg: Equatable, Sendable {
    public var step: String
    public var status: StepStatus

    public init(step: String, status: StepStatus) {
        self.step = step
        self.status = status
    }
}

extension PlanItemArg: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case step
        case status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "PlanItemArg")
        step = try container.decode(String.self, forKey: .step)
        status = try container.decode(StepStatus.self, forKey: .status)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step, forKey: .step)
        try container.encode(status, forKey: .status)
    }
}

/// serde `deny_unknown_fields`.
public struct UpdatePlanArgs: Equatable, Sendable {
    /// Arguments for the `update_plan` todo/checklist tool (not plan mode).
    public var explanation: String?
    public var plan: [PlanItemArg]

    public init(explanation: String? = nil, plan: [PlanItemArg]) {
        self.explanation = explanation
        self.plan = plan
    }
}

extension UpdatePlanArgs: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case explanation
        case plan
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "UpdatePlanArgs")
        // `#[serde(default)]`: missing or null → None.
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        plan = try container.decode([PlanItemArg].self, forKey: .plan)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // No skip_serializing_if upstream: None encodes as explicit null.
        try container.encode(explanation, forKey: .explanation)
        try container.encode(plan, forKey: .plan)
    }
}
