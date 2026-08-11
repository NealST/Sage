//
//  SkillSuggestionQueue.swift
//  Sage
//
//  Manages pending skill suggestions with debounced UI notification.
//  Collects extraction results and aggregates them before presenting to the user.
//

import Foundation

/// A suggestion to create or enhance a skill, pending user confirmation.
/// Identification only — full skill content is composed after the user confirms.
struct SkillSuggestion: Identifiable, Sendable {
    let id: UUID
    let type: SuggestionType
    let skillName: String
    let skillDescription: String
    /// Resolved write/recall scope. For new skills in a project, may be overridden
    /// by the banner when `allowsScopeChoice` is true.
    let scope: SkillScope
    /// When true (new skill while focused on a project), the banner asks whether
    /// to save under the current project or as a global skill.
    let allowsScopeChoice: Bool
    /// Absolute project root captured at identification time (for project-scoped writes).
    let projectRootPath: String?
    /// Absolute SKILL.md path pinned at identification for enhance (avoids live lookup).
    let targetSkillPath: String?
    /// The task that generated this suggestion.
    let sourceTaskID: UUID
    let createdAt: Date

    enum SuggestionType: Sendable, Equatable {
        case new
        case enhance
    }

    init(
        id: UUID = UUID(),
        type: SuggestionType,
        skillName: String,
        skillDescription: String,
        scope: SkillScope,
        allowsScopeChoice: Bool = false,
        projectRootPath: String? = nil,
        targetSkillPath: String? = nil,
        sourceTaskID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.skillName = skillName
        self.skillDescription = skillDescription
        self.scope = scope
        self.allowsScopeChoice = allowsScopeChoice
        self.projectRootPath = projectRootPath
        self.targetSkillPath = targetSkillPath
        self.sourceTaskID = sourceTaskID
        self.createdAt = createdAt
    }

    /// Returns a copy with an explicit write scope (after the user chooses in the banner).
    func resolved(scope: SkillScope) -> SkillSuggestion {
        SkillSuggestion(
            id: id,
            type: type,
            skillName: skillName,
            skillDescription: skillDescription,
            scope: scope,
            allowsScopeChoice: false,
            projectRootPath: projectRootPath,
            targetSkillPath: targetSkillPath,
            sourceTaskID: sourceTaskID,
            createdAt: createdAt
        )
    }
}

/// Collects skill suggestions and debounces UI presentation.
///
/// When a suggestion arrives, it's buffered for `debounceInterval` seconds.
/// If more suggestions arrive within that window, they're aggregated into a single
/// UI notification batch.
@MainActor
@Observable
final class SkillSuggestionQueue {
    /// Suggestions ready to be shown to the user (after debounce).
    private(set) var pendingSuggestions: [SkillSuggestion] = []

    /// Whether the banner should be visible.
    var showBanner: Bool { !pendingSuggestions.isEmpty }

    private let debounceInterval: TimeInterval
    private var buffer: [SkillSuggestion] = []
    private var debounceTask: Task<Void, Never>?

    init(debounceInterval: TimeInterval = 10.0) {
        self.debounceInterval = debounceInterval
    }

    /// Enqueues a suggestion. Triggers debounce timer for batch presentation.
    func enqueue(_ suggestion: SkillSuggestion) {
        buffer.append(suggestion)
        scheduleFlush()
    }

    /// Enqueues and shows immediately (used for explicit `/remember`).
    func enqueueImmediate(_ suggestion: SkillSuggestion) {
        debounceTask?.cancel()
        debounceTask = nil
        if !buffer.isEmpty {
            pendingSuggestions.append(contentsOf: buffer)
            buffer.removeAll()
        }
        pendingSuggestions.append(suggestion)
    }

    /// Confirms a suggestion — caller should write the skill to disk.
    /// Returns the confirmed suggestion for processing.
    func confirm(_ suggestionID: UUID) -> SkillSuggestion? {
        guard let index = pendingSuggestions.firstIndex(where: { $0.id == suggestionID }) else {
            return nil
        }
        return pendingSuggestions.remove(at: index)
    }

    /// Dismisses a suggestion without saving.
    func dismiss(_ suggestionID: UUID) {
        pendingSuggestions.removeAll { $0.id == suggestionID }
    }

    /// Dismisses all pending suggestions.
    func dismissAll() {
        pendingSuggestions.removeAll()
    }

    // MARK: - Debounce

    private func scheduleFlush() {
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
    }

    private func flush() {
        guard !buffer.isEmpty else { return }
        pendingSuggestions.append(contentsOf: buffer)
        buffer.removeAll()
    }
}
