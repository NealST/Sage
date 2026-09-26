//
//  audit.swift
//  CodexState
//
//  Port of codex-rs/state/src/audit.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Read-only sqlx pool access is omitted until a GRDB connection exists.
//  The query shape and row type are preserved.
//

import Foundation

/// Minimal thread metadata used by read-only state database audits.
public struct ThreadStateAuditRow: Equatable, Sendable {
    public var id: String
    public var rolloutPath: String
    public var archived: Bool
    public var source: String
    public var modelProvider: String

    public init(
        id: String,
        rolloutPath: String,
        archived: Bool,
        source: String,
        modelProvider: String
    ) {
        self.id = id
        self.rolloutPath = rolloutPath
        self.archived = archived
        self.source = source
        self.modelProvider = modelProvider
    }
}

/// Read persisted thread rows from a state DB without creating, migrating, or repairing it.
public func readThreadStateAuditRows(_ sqlite: SqliteConfig) async throws -> [ThreadStateAuditRow] {
    throw StateRuntimeError.sqliteUnavailable("state")
}
