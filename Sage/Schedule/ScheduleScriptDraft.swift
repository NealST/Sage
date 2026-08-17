//
//  ScheduleScriptDraft.swift
//  Sage
//

import Foundation

nonisolated struct ScheduleScriptDraft: Equatable {
    var command: String
    var cadence: ScheduleCadence
    var cadencePresetInsert: String
    let openedAt: Date

    static func blank() -> ScheduleScriptDraft {
        ScheduleScriptDraft(
            command: "",
            cadence: .weekdays(hour: 9, minute: 0),
            cadencePresetInsert: "weekdays 9:00",
            openedAt: .now
        )
    }
}
