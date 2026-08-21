//
//  SkillEnhanceInput.swift
//  Sage
//

import Foundation

nonisolated struct SkillEnhanceInput: Sendable {
    var skillName: String
    var currentDescription: String
    var currentBody: String
    var suggestedDescription: String
    var task: TaskRecord
    var settings: ModelSettingsSnapshot
}
