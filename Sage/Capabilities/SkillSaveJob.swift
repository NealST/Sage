//
//  SkillSaveJob.swift
//  Sage
//
//  Tracks in-flight and recent skill create/enhance jobs started from the banner.
//

import Foundation

/// A background skill create/enhance job started after the user confirms a banner tip.
struct SkillSaveJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: SkillSuggestion.SuggestionType
    let skillName: String
    var status: Status
    let startedAt: Date

    enum Status: Equatable, Sendable {
        case running
        case succeeded
        case failed(String)
    }

    init(
        id: UUID = UUID(),
        type: SkillSuggestion.SuggestionType,
        skillName: String,
        status: Status = .running,
        startedAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.skillName = skillName
        self.status = status
        self.startedAt = startedAt
    }

    var title: String {
        switch type {
        case .new:
            return "Creating \(skillName)"
        case .enhance:
            return "Enhancing \(skillName)"
        case .merge:
            return "Merging into \(skillName)"
        }
    }

    var statusLabel: String {
        switch status {
        case .running:
            switch type {
            case .new: return "Creating…"
            case .enhance: return "Enhancing…"
            case .merge: return "Merging…"
            }
        case .succeeded:
            return "Saved"
        case .failed(let message):
            return message
        }
    }
}
