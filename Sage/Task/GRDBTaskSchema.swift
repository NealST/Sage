//
//  GRDBTaskSchema.swift
//  Sage
//
//  Schema SQL + migrations for GRDBTaskRepository.
//

import Foundation
import GRDB

nonisolated enum GRDBTaskSchema {
    static let schemaSQL = """
    CREATE TABLE tasks (
        id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL,
        summary TEXT,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE INDEX tasks_updated_at
    ON tasks(updated_at DESC);

    CREATE TABLE app_state (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        active_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL
    );

    CREATE TABLE events (
        id TEXT PRIMARY KEY NOT NULL,
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        sequence INTEGER NOT NULL,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        tool_call_id TEXT,
        protected INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        UNIQUE(task_id, sequence)
    );

    CREATE INDEX events_task_sequence
    ON events(task_id, sequence);

    CREATE TABLE event_tool_calls (
        event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        call_id TEXT NOT NULL,
        name TEXT NOT NULL,
        arguments_json TEXT NOT NULL,
        PRIMARY KEY(event_id, position)
    );

    CREATE TABLE event_contexts (
        event_id TEXT PRIMARY KEY NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        confidence REAL NOT NULL,
        reason TEXT NOT NULL
    );

    CREATE TABLE event_context_tasks (
        event_id TEXT NOT NULL REFERENCES event_contexts(event_id) ON DELETE CASCADE,
        related_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        PRIMARY KEY(event_id, related_task_id)
    );

    CREATE TABLE task_entities (
        id TEXT PRIMARY KEY NOT NULL,
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        value TEXT NOT NULL,
        UNIQUE(task_id, kind, value)
    );

    CREATE INDEX task_entities_lookup
    ON task_entities(kind, value);

    CREATE TABLE task_relations (
        source_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        target_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        PRIMARY KEY(source_task_id, target_task_id)
    );

    CREATE TABLE plans (
        id TEXT PRIMARY KEY NOT NULL,
        task_id TEXT UNIQUE NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        summary TEXT NOT NULL
    );

    CREATE TABLE plan_steps (
        id TEXT PRIMARY KEY NOT NULL,
        plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        tool_call_id TEXT NOT NULL,
        tool_name TEXT NOT NULL,
        arguments_json TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        result TEXT,
        UNIQUE(plan_id, position)
    );
    """
}
