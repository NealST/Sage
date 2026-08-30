//
//  ReviewAgent.swift
//  Sage
//
//  Sub-agent: judge whether the work plan was fulfilled. No tools.
//

import Foundation

nonisolated struct ReviewVerdict: Sendable, Equatable {
    enum Decision: String, Sendable {
        case accept
        case revise
    }

    var decision: Decision
    /// Short note. For revise, this is what the execute agent should fix.
    var feedback: String
}

enum ReviewEvaluationError: LocalizedError {
    case unusable(String)

    var errorDescription: String? {
        switch self {
        case .unusable(let detail):
            return detail.nilIfEmpty ?? "The reviewer could not produce a usable verdict."
        }
    }
}

@MainActor
final class ReviewAgent {
    static let maxRevisions = 2
    static let maxAttempts = 3

    private let state: AgentSessionState
    private let modelGateway: AgentModelGateway

    init(state: AgentSessionState, modelGateway: AgentModelGateway) {
        self.state = state
        self.modelGateway = modelGateway
    }

    func evaluate(draft: String, changes: WorkspaceChangeSet) async throws -> ReviewVerdict {
        let brief = Self.brief(
            userText: state.events.last { $0.kind == .userInput }?
                .modelFacingContent(includeImagePixels: false) ?? "",
            plan: state.activeTask?.workPlan,
            draft: draft,
            turnDigest: TranscriptDigest.makeCurrentTurn(from: state.events),
            changes: changes
        )
        var lastDetail = "The reviewer returned unusable output."
        for _ in 1...Self.maxAttempts {
            try Task.checkCancellation()
            do {
                let raw = try await modelGateway.completeUnstreamed(
                    system: Self.systemPrompt,
                    user: brief,
                    role: .review
                )
                if let verdict = Self.parse(raw) { return verdict }
                lastDetail = "The reviewer returned unusable output."
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastDetail = error.localizedDescription
            }
        }
        throw ReviewEvaluationError.unusable(lastDetail)
    }

    nonisolated static func parse(_ raw: String?) -> ReviewVerdict? {
        guard let object = ModelJSON.object(from: raw),
              let decisionRaw = object["decision"] as? String,
              let decision = ReviewVerdict.Decision(rawValue: decisionRaw)
        else { return nil }
        let feedback = (object["feedback"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ReviewVerdict(decision: decision, feedback: feedback)
    }
}
