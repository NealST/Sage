//
//  external_agent_config_imports.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/external_agent_config_imports.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  INSERT / SELECT SQL throws until a state pool exists. Record types match
//  upstream; `PathBuf` maps to `String`.
//

import Foundation

public struct ExternalAgentConfigImportSuccessRecord: Codable, Equatable, Sendable {
    public var itemType: String
    public var cwd: String?
    public var source: String?
    public var target: String?
    public var title: String?

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case cwd, source, target, title
    }

    public init(
        itemType: String,
        cwd: String? = nil,
        source: String? = nil,
        target: String? = nil,
        title: String? = nil
    ) {
        self.itemType = itemType
        self.cwd = cwd
        self.source = source
        self.target = target
        self.title = title
    }
}

public struct ExternalAgentConfigImportFailureRecord: Codable, Equatable, Sendable {
    public var itemType: String
    public var errorType: String?
    public var subErrorType: String?
    public var failureStage: String
    public var message: String
    public var cwd: String?
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case errorType = "error_type"
        case subErrorType = "sub_error_type"
        case failureStage = "failure_stage"
        case message, cwd, source
    }

    public init(
        itemType: String,
        errorType: String? = nil,
        subErrorType: String? = nil,
        failureStage: String,
        message: String,
        cwd: String? = nil,
        source: String? = nil
    ) {
        self.itemType = itemType
        self.errorType = errorType
        self.subErrorType = subErrorType
        self.failureStage = failureStage
        self.message = message
        self.cwd = cwd
        self.source = source
    }
}

public struct ExternalAgentConfigImportDetailsRecord: Codable, Equatable, Sendable {
    public var successes: [ExternalAgentConfigImportSuccessRecord]
    public var failures: [ExternalAgentConfigImportFailureRecord]

    public init(
        successes: [ExternalAgentConfigImportSuccessRecord],
        failures: [ExternalAgentConfigImportFailureRecord]
    ) {
        self.successes = successes
        self.failures = failures
    }
}

public struct ExternalAgentConfigImportHistoryRecord: Codable, Equatable, Sendable {
    public var importId: String
    public var providerId: String?
    public var completedAtMs: Int64
    public var successes: [ExternalAgentConfigImportSuccessRecord]
    public var failures: [ExternalAgentConfigImportFailureRecord]

    enum CodingKeys: String, CodingKey {
        case importId = "import_id"
        case providerId = "provider_id"
        case completedAtMs = "completed_at_ms"
        case successes, failures
    }

    public init(
        importId: String,
        providerId: String? = nil,
        completedAtMs: Int64,
        successes: [ExternalAgentConfigImportSuccessRecord],
        failures: [ExternalAgentConfigImportFailureRecord]
    ) {
        self.importId = importId
        self.providerId = providerId
        self.completedAtMs = completedAtMs
        self.successes = successes
        self.failures = failures
    }
}

extension StateRuntime {
    public func recordExternalAgentConfigImportCompleted(
        importId: String,
        providerId: String?,
        successes: [ExternalAgentConfigImportSuccessRecord],
        failures: [ExternalAgentConfigImportFailureRecord]
    ) async throws {
        _ = datetimeToEpochMillis(Date())
        _ = importId
        _ = providerId
        _ = successes
        _ = failures
        throw StateRuntimeError.sqliteUnavailable("external_agent_config_imports")
    }

    public func externalAgentConfigImportDetailsRecord(
        importId: String
    ) async throws -> ExternalAgentConfigImportDetailsRecord? {
        _ = importId
        throw StateRuntimeError.sqliteUnavailable("external_agent_config_imports")
    }

    public func externalAgentConfigImportHistoryRecords() async throws -> [ExternalAgentConfigImportHistoryRecord] {
        throw StateRuntimeError.sqliteUnavailable("external_agent_config_imports")
    }
}
