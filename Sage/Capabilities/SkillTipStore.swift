//
//  SkillTipStore.swift
//  Sage
//
//  Single tip surface for save / choose / consolidate prompts above the composer.
//

import Foundation

/// A suggestion to create or enhance a skill, pending user confirmation.
nonisolated struct SkillSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: SuggestionType
    let skillName: String
    let skillDescription: String
    let scope: SkillScope
    let allowsScopeChoice: Bool
    let projectRootPath: String?
    let targetSkillPath: String?
    let sourceTaskID: UUID
    let createdAt: Date

    nonisolated enum SuggestionType: Sendable, Equatable {
        case new
        case enhance
        case merge
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

/// Typed tip items shared by save + recall UI.
nonisolated enum SkillTipItem: Identifiable, Equatable, Sendable {
    case save(SkillSuggestion)
    case choose(SkillActivationChoice)
    case consolidate(SkillConsolidateSuggestion)
    case schedule(ScheduleDraft)

    var id: UUID {
        switch self {
        case .save(let suggestion): return suggestion.id
        case .choose(let choice): return choice.id
        case .consolidate(let suggestion): return suggestion.id
        case .schedule(let draft): return draft.id
        }
    }

    /// Choose tips pause the turn and must not auto-dismiss.
    var allowsAutoDismiss: Bool {
        switch self {
        case .choose: return false
        case .save, .consolidate, .schedule: return true
        }
    }
}

/// Unified tip store: debounced save suggestions + immediate recall prompts.
@MainActor
@Observable
final class SkillTipStore {
    private(set) var items: [SkillTipItem] = []
    /// Bumped on every items mutation — prefer over `items.map(\.id)` for SwiftUI onChange.
    private(set) var revision: UInt64 = 0

    var showBanner: Bool { !items.isEmpty }

    private func noteMutation() {
        revision &+= 1
    }

    var pendingSuggestions: [SkillSuggestion] {
        items.compactMap {
            if case .save(let suggestion) = $0 { return suggestion }
            return nil
        }
    }

    var choosePrompt: SkillActivationChoice? {
        for item in items {
            if case .choose(let choice) = item { return choice }
        }
        return nil
    }

    private let debounceInterval: TimeInterval
    private var saveBuffer: [SkillSuggestion] = []
    private var debounceTask: Task<Void, Never>?

    init(debounceInterval: TimeInterval = 10.0) {
        self.debounceInterval = debounceInterval
    }

    // MARK: - Save tips

    func enqueueSave(_ suggestion: SkillSuggestion) {
        removeSaveDuplicates(of: suggestion)
        saveBuffer.append(suggestion)
        scheduleFlush()
    }

    func enqueueSaveImmediate(_ suggestion: SkillSuggestion) {
        debounceTask?.cancel()
        debounceTask = nil
        removeSaveDuplicates(of: suggestion)
        if !saveBuffer.isEmpty {
            items.append(contentsOf: saveBuffer.map { .save($0) })
            saveBuffer.removeAll()
        }
        items.append(.save(suggestion))
        noteMutation()
    }

    @discardableResult
    func confirmSave(_ suggestionID: UUID) -> SkillSuggestion? {
        guard let index = items.firstIndex(where: {
            if case .save(let suggestion) = $0 { return suggestion.id == suggestionID }
            return false
        }) else { return nil }
        guard case .save(let suggestion) = items.remove(at: index) else { return nil }
        noteMutation()
        return suggestion
    }

    func enqueueSchedule(_ draft: ScheduleDraft) {
        items.removeAll {
            if case .schedule = $0 { return true }
            return false
        }
        items.append(.schedule(draft))
        noteMutation()
    }

    func updateSchedule(_ id: UUID, mutate: (inout ScheduleDraft) -> Void) {
        guard let index = items.firstIndex(where: {
            if case .schedule(let draft) = $0 { return draft.id == id }
            return false
        }) else { return }
        guard case .schedule(var draft) = items[index] else { return }
        mutate(&draft)
        items[index] = .schedule(draft)
        noteMutation()
    }

    @discardableResult
    func confirmSchedule(_ id: UUID) -> ScheduleDraft? {
        guard let index = items.firstIndex(where: {
            if case .schedule(let draft) = $0 { return draft.id == id }
            return false
        }) else { return nil }
        guard case .schedule(let draft) = items.remove(at: index) else { return nil }
        noteMutation()
        return draft
    }

    // MARK: - Recall tips

    func enqueueChoose(_ choice: SkillActivationChoice) {
        items.removeAll {
            if case .choose = $0 { return true }
            return false
        }
        items.insert(.choose(choice), at: 0)
        noteMutation()
    }

    func enqueueConsolidate(_ suggestion: SkillConsolidateSuggestion) {
        let key = Set(suggestion.candidates.map(\.path))
        let exists = items.contains {
            guard case .consolidate(let existing) = $0 else { return false }
            return Set(existing.candidates.map(\.path)) == key
        }
        guard !exists else { return }
        items.append(.consolidate(suggestion))
        noteMutation()
    }

    func dismissChoose() {
        let before = items.count
        items.removeAll {
            if case .choose = $0 { return true }
            return false
        }
        if items.count != before { noteMutation() }
    }

    // MARK: - Shared

    func dismiss(_ id: UUID) {
        let before = items.count
        items.removeAll { $0.id == id }
        saveBuffer.removeAll { $0.id == id }
        if items.count != before { noteMutation() }
    }

    func dismissAll() {
        debounceTask?.cancel()
        debounceTask = nil
        saveBuffer.removeAll()
        if !items.isEmpty {
            items.removeAll()
            noteMutation()
        }
    }

    func dismissAutoDismissable() {
        let before = items.count
        items.removeAll { $0.allowsAutoDismiss }
        // Keep buffered saves (not yet shown); they are not on screen.
        if items.count != before { noteMutation() }
    }

    // MARK: - Debounce

    private func removeSaveDuplicates(of suggestion: SkillSuggestion) {
        saveBuffer.removeAll { $0.skillName == suggestion.skillName && $0.type == suggestion.type }
        let before = items.count
        items.removeAll {
            guard case .save(let existing) = $0 else { return false }
            return existing.skillName == suggestion.skillName && existing.type == suggestion.type
        }
        if items.count != before { noteMutation() }
    }

    private func scheduleFlush() {
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            self.flushSaveBuffer()
        }
    }

    private func flushSaveBuffer() {
        guard !saveBuffer.isEmpty else { return }
        items.append(contentsOf: saveBuffer.map { .save($0) })
        saveBuffer.removeAll()
        noteMutation()
    }
}
