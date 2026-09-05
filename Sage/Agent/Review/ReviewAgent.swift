//
//  ReviewAgent.swift
//  Sage
//
//  Sub-agent: inspect the current world against the confirmed contract.
//  Read-only tools. Does not write, compile, or test.
//

import Foundation

nonisolated struct ReviewVerdict: Sendable, Equatable {
    /// Holes, bugs, or missing work. Empty means none.
    var mustFix: String?
    /// Quality or UX improvements the user can decline. Empty means none.
    var optional: String?

    var hasMustFix: Bool { !(mustFix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    var hasOptional: Bool { !(optional?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }

    static func mustFixOnly(_ message: String) -> Self {
        Self(mustFix: message, optional: nil)
    }
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
    static let maxInspectRounds = 6

    static let inspectToolNames: Set<String> = [
        "list_directory",
        "read_text_file",
        "search_files",
        "get_clipboard",
        "get_selected_text",
        "get_screen_info",
        "get_frontmost_app",
        "get_system_volume",
    ]

    let state: AgentSessionState
    let modelGateway: AgentModelGateway
    weak var skillHost: SkillToolHost?

    init(state: AgentSessionState, modelGateway: AgentModelGateway) {
        self.state = state
        self.modelGateway = modelGateway
    }

    func evaluate(draft: String, workPlan: WorkPlan?) async throws -> ReviewVerdict {
        let brief = Self.brief(
            userText: state.events.last { $0.kind == .userInput }?
                .modelFacingContent(includeImagePixels: false) ?? "",
            workPlan: workPlan,
            draft: draft,
            sandbox: state.pathGuardPolicy.boundaryDescription,
            inspectPlaces: state.workspaceChanges.snapshot().inspectPlaces()
        )
        let tools = inspectToolDefinitions()
        var lastDetail = "The reviewer returned unusable output."
        for _ in 1...Self.maxAttempts {
            try Task.checkCancellation()
            do {
                if let verdict = try await inspect(brief: brief, tools: tools) {
                    return verdict
                }
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
        guard let object = ModelJSON.object(from: raw) else { return nil }
        if object["must_fix"] != nil || object["optional"] != nil {
            return ReviewVerdict(
                mustFix: stringField(object["must_fix"]),
                optional: stringField(object["optional"])
            )
        }
        guard let decisionRaw = object["decision"] as? String else { return nil }
        let feedback = stringField(object["feedback"])
        switch decisionRaw {
        case "accept":
            return ReviewVerdict(mustFix: nil, optional: nil)

        case "revise":
            return .mustFixOnly(feedback ?? "The result does not fully match the plan.")

        default:
            return nil
        }
    }

    private nonisolated static func stringField(_ value: Any?) -> String? {
        let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
