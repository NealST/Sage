//
//  PlanProgress.swift
//  Sage
//
//  In-flight tool-batch progress for the execute agent — not WorkPlan.
//  Step updates do not rewrite AgentPhase, so transcript chrome stays stable.
//

import Foundation

@MainActor
@Observable
final class PlanProgress {
    private(set) var plan: AgentPlan?

    var summary: String {
        plan?.summary ?? ""
    }

    var steps: [AgentStep] {
        plan?.steps ?? []
    }

    var hasPlan: Bool { plan != nil }

    func replace(_ plan: AgentPlan?) {
        self.plan = plan
    }

    func updateStep(_ step: AgentStep) {
        guard var plan else { return }
        guard let index = plan.steps.firstIndex(where: { $0.id == step.id }) else { return }
        plan.steps[index] = step
        self.plan = plan
    }

    func update(_ plan: AgentPlan) {
        self.plan = plan
    }

    func clear() {
        plan = nil
    }
}
