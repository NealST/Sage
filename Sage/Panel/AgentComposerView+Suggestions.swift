//
//  AgentComposerView+Suggestions.swift
//  Sage
//
//  Slash-command suggestion updates for the composer.
//

import SwiftUI

extension AgentComposerView {
    func updateSkillSuggestions(_ draft: String) {
        let lowered = draft.lowercased()
        let next: [ComposerSlashSuggestion]
        if lowered.hasPrefix("/schedule"), !lowered.hasPrefix("/schedule-") {
            next = ScheduleCadenceParser.autocompleteInserts(forDraft: draft).map { insert in
                ComposerSlashSuggestion(
                    id: insert.id,
                    title: "/schedule \(insert.insert)",
                    description: insert.description,
                    insertDraft: "/schedule \(insert.insert) ",
                    submitOnSelect: false,
                    systemImage: "clock"
                )
            }
        } else if draft.hasPrefix("/"), !draft.contains(" ") {
            let prefix = String(draft.dropFirst()).lowercased()
            let available = session.agent.availableSlashCommandDefinitions
            let filtered = prefix.isEmpty
                ? available
                : available.filter { $0.name.lowercased().hasPrefix(prefix) }
            next = Array(filtered.prefix(6)).map { command in
                let isSchedule = command.name == "schedule"
                return ComposerSlashSuggestion(
                    id: command.name,
                    title: "/\(command.name)",
                    description: command.description,
                    insertDraft: isSchedule ? "/schedule " : "/\(command.name)",
                    submitOnSelect: !isSchedule,
                    systemImage: command.kind == .builtin ? "bookmark" : "sparkles"
                )
            }
        } else {
            next = []
        }
        withAnimation(.easeOut(duration: 0.15)) {
            let resetIndex = slashSuggestions.isEmpty
            slashSuggestions = next
            if resetIndex || !next.indices.contains(selectedSuggestionIndex) {
                selectedSuggestionIndex = 0
            }
        }
    }
}

struct ComposerSlashSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let insertDraft: String
    let submitOnSelect: Bool
    let systemImage: String
}
