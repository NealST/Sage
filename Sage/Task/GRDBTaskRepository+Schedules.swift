//
//  GRDBTaskRepository+Schedules.swift
//  Sage
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    func listSchedules() throws -> [ScheduleRecord] {
        let pool = try database()
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM schedules
                ORDER BY next_fire_at IS NULL, next_fire_at ASC, updated_at DESC
                """
            )
            return rows.compactMap { Self.schedule(from: $0) }
        }
    }

    func loadSchedule(id: UUID) throws -> ScheduleRecord? {
        let pool = try database()
        return try pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM schedules WHERE id = ?",
                arguments: [id.uuidString]
            )
            return row.flatMap { Self.schedule(from: $0) }
        }
    }

    func upsertSchedule(_ schedule: ScheduleRecord) throws {
        let pool = try database()
        let cadenceKind: String
        let cadenceJSON: String
        switch schedule.cadence {
        case .once(let date):
            cadenceKind = "once"
            cadenceJSON = Self.jsonObject(["date": date.timeIntervalSince1970])
        case .interval(let seconds):
            cadenceKind = "interval"
            cadenceJSON = Self.jsonObject(["seconds": seconds])
        case .weekdays(let hour, let minute):
            cadenceKind = "weekdays"
            cadenceJSON = Self.jsonObject(["hour": hour, "minute": minute])
        case .daily(let hour, let minute):
            cadenceKind = "daily"
            cadenceJSON = Self.jsonObject(["hour": hour, "minute": minute])
        case .delay(let seconds):
            cadenceKind = "delay"
            cadenceJSON = Self.jsonObject(["seconds": seconds])
        }
        let skillsJSON = Self.encodeJSON(schedule.frozenSkillNames)
        try pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO schedules (
                    id, title, kind, project_id, prompt, command, working_directory,
                    cadence_kind, cadence_json, enabled, status,
                    next_fire_at, last_fire_at, last_status,
                    frozen_work_plan_json, frozen_skill_names, origin_task_id,
                    last_run_task_id, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    kind = excluded.kind,
                    project_id = excluded.project_id,
                    prompt = excluded.prompt,
                    command = excluded.command,
                    working_directory = excluded.working_directory,
                    cadence_kind = excluded.cadence_kind,
                    cadence_json = excluded.cadence_json,
                    enabled = excluded.enabled,
                    status = excluded.status,
                    next_fire_at = excluded.next_fire_at,
                    last_fire_at = excluded.last_fire_at,
                    last_status = excluded.last_status,
                    frozen_work_plan_json = excluded.frozen_work_plan_json,
                    frozen_skill_names = excluded.frozen_skill_names,
                    origin_task_id = excluded.origin_task_id,
                    last_run_task_id = excluded.last_run_task_id,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    schedule.id.uuidString,
                    schedule.title,
                    schedule.kind.rawValue,
                    schedule.projectID?.uuidString,
                    schedule.prompt,
                    schedule.command,
                    schedule.workingDirectory,
                    cadenceKind,
                    cadenceJSON,
                    schedule.enabled ? 1 : 0,
                    schedule.status.rawValue,
                    schedule.nextFireAt?.timeIntervalSince1970,
                    schedule.lastFireAt?.timeIntervalSince1970,
                    schedule.lastStatus,
                    schedule.frozenWorkPlanJSON,
                    skillsJSON,
                    schedule.originTaskID?.uuidString,
                    schedule.lastRunTaskID?.uuidString,
                    schedule.createdAt.timeIntervalSince1970,
                    schedule.updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func deleteSchedule(id: UUID) throws {
        let pool = try database()
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM schedules WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func dueSchedules(at date: Date) throws -> [ScheduleRecord] {
        let pool = try database()
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM schedules
                WHERE enabled = 1
                  AND status IN (?, ?)
                  AND next_fire_at IS NOT NULL
                  AND next_fire_at <= ?
                ORDER BY next_fire_at ASC
                """,
                arguments: [
                    ScheduleStatus.needsFirstRun.rawValue,
                    ScheduleStatus.armed.rawValue,
                    date.timeIntervalSince1970,
                ]
            )
            return rows.compactMap { Self.schedule(from: $0) }
        }
    }

    func insertScheduleRun(
        id: UUID,
        scheduleID: UUID,
        startedAt: Date,
        endedAt: Date?,
        exitCode: Int32?,
        outputExcerpt: String?
    ) throws {
        let pool = try database()
        try pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO schedule_runs (
                    id, schedule_id, started_at, ended_at, exit_code, output_excerpt
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id.uuidString,
                    scheduleID.uuidString,
                    startedAt.timeIntervalSince1970,
                    endedAt?.timeIntervalSince1970,
                    exitCode.map { Int($0) },
                    outputExcerpt,
                ]
            )
        }
    }

    func latestScheduleRun(scheduleID: UUID) throws -> ScheduleRunRecord? {
        let pool = try database()
        return try pool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT * FROM schedule_runs
                WHERE schedule_id = ?
                ORDER BY started_at DESC
                LIMIT 1
                """,
                arguments: [scheduleID.uuidString]
            )
            return row.flatMap { Self.scheduleRun(from: $0) }
        }
    }

    private static func scheduleRun(from row: Row) -> ScheduleRunRecord? {
        guard let id = UUID(uuidString: row["id"]),
              let scheduleID = UUID(uuidString: row["schedule_id"])
        else { return nil }
        let exit: Int32?
        if let value = row["exit_code"] as Int? {
            exit = Int32(value)
        } else {
            exit = nil
        }
        return ScheduleRunRecord(
            id: id,
            scheduleID: scheduleID,
            startedAt: Date(timeIntervalSince1970: row["started_at"]),
            endedAt: (row["ended_at"] as Double?).map { Date(timeIntervalSince1970: $0) },
            exitCode: exit,
            outputExcerpt: row["output_excerpt"]
        )
    }

    private static func jsonObject(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static func encodeJSON(_ value: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func schedule(from row: Row) -> ScheduleRecord? {
        guard let id = UUID(uuidString: row["id"]),
              let kind = ScheduleKind(rawValue: row["kind"]),
              let status = ScheduleStatus(rawValue: row["status"]),
              let cadenceKind: String = row["cadence_kind"],
              let cadenceJSON: String = row["cadence_json"],
              let cadence = decodeCadence(kind: cadenceKind, json: cadenceJSON)
        else { return nil }

        let skills: [String]
        if let raw = row["frozen_skill_names"] as String?,
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            skills = decoded
        } else {
            skills = []
        }

        return ScheduleRecord(
            id: id,
            title: row["title"],
            kind: kind,
            projectID: (row["project_id"] as String?).flatMap(UUID.init(uuidString:)),
            prompt: row["prompt"],
            command: row["command"],
            workingDirectory: row["working_directory"],
            cadence: cadence,
            enabled: (row["enabled"] as Int) != 0,
            status: status,
            nextFireAt: (row["next_fire_at"] as Double?).map { Date(timeIntervalSince1970: $0) },
            lastFireAt: (row["last_fire_at"] as Double?).map { Date(timeIntervalSince1970: $0) },
            lastStatus: row["last_status"],
            frozenWorkPlanJSON: row["frozen_work_plan_json"],
            frozenSkillNames: skills,
            originTaskID: (row["origin_task_id"] as String?).flatMap(UUID.init(uuidString:)),
            lastRunTaskID: (row["last_run_task_id"] as String?).flatMap(UUID.init(uuidString:)),
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }

    private static func decodeCadence(kind: String, json: String) -> ScheduleCadence? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        switch kind {
        case "once":
            guard let interval = number(object["date"]) else { return nil }
            return .once(date: Date(timeIntervalSince1970: interval))
        case "interval":
            guard let seconds = number(object["seconds"]) else { return nil }
            return .interval(seconds: seconds)
        case "weekdays":
            guard let hour = int(object["hour"]), let minute = int(object["minute"]) else {
                return nil
            }
            return .weekdays(hour: hour, minute: minute)
        case "daily":
            guard let hour = int(object["hour"]), let minute = int(object["minute"]) else {
                return nil
            }
            return .daily(hour: hour, minute: minute)
        case "delay":
            guard let seconds = number(object["seconds"]) else { return nil }
            return .delay(seconds: seconds)
        default:
            return nil
        }
    }

    private static func number(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func int(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let value = any as? NSNumber { return value.intValue }
        return nil
    }
}
