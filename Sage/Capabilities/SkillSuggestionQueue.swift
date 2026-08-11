//
//  SkillSuggestionQueue.swift
//  Sage
//
//  Manages pending skill suggestions with debounced UI notification.
//  Collects extraction results and aggregates them before presenting to the user.
//

import Foundation

/// A suggestion to create or enhance a skill, pending user confirmation.
struct SkillSuggestion: Identifiable, Sendable {
    let id: UUID
    let type: SuggestionType
    let skillName: String
    let skillDescription: String
    /// Full SKILL.md content to write.
    let body: String
    /// The task that generated this suggestion.
    let sourceTaskID: UUID
    let createdAt: Date

    enum SuggestionType: Sendable {
        case new
        case enhance
    }

    init(
        id: UUID = UUID(),
        type: SuggestionType,
        skillName: String,
        skillDescription: String,
        body: String,
        sourceTaskID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.skillName = skillName
        self.skillDescription = skillDescription
        self.body = body
        self.sourceTaskID = sourceTaskID
        self.createdAt = createdAt
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
