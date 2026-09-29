//
//  auth_storage.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/auth_storage.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Classification enums + StorageTelemetry drop emission are faithful.
//  Error downcast uses IOError / NSError instead of std::io::Error.
//

import CodexUtils
import Foundation
import os

public enum CredentialKind: String, Equatable, Sendable {
    case codex
    case mcp
}

public enum StoreMode: String, Equatable, Sendable {
    case file
    case auto
    case keyring
    case ephemeral
}

public enum Store: String, Equatable, Sendable {
    case file
    case directKeyring = "direct_keyring"
    case secrets
    case ephemeral
    case multiple
}

public enum Operation: String, Equatable, Sendable {
    case load
    case save
    case delete
    case cleanup
    case refreshPersist = "refresh_persist"
}

enum Outcome: String, Equatable, Sendable {
    case notAttempted = "not_attempted"
    case success
    case notFound = "not_found"
    case error
}

public enum StoragePhase: String, Equatable, Sendable {
    case policy
    case pinned
}

private struct Observation {
    var credentialKind: CredentialKind
    var mode: StoreMode
    var selectedStore: Store
    var actualStore: Store
    var operation: Operation
    var secureOutcome: Outcome
    var outcome: Outcome
    var duration: Duration
    var phase: StoragePhase
    var secureError: String
    var originator: AuthStorageOriginator

    func record() {
        let fallback: String
        switch (mode, phase, actualStore, secureOutcome) {
        case (.auto, .policy, .file, .error):
            fallback = "secure_error"
        case (.auto, .policy, .file, .notFound):
            fallback = "secure_entry_missing"
        default:
            fallback = "none"
        }
        let tags = [
            ("credential_kind", credentialKind.rawValue),
            ("store_mode", mode.rawValue),
            ("selected_store", selectedStore.rawValue),
            ("actual_store", actualStore.rawValue),
            ("operation", operation.rawValue),
            ("secure_outcome", secureOutcome.rawValue),
            ("outcome", outcome.rawValue),
            ("fallback_reason", fallback),
            ("secure_error", secureError),
            ("storage_phase", phase.rawValue),
            (ORIGINATOR_TAG, originator.asStr()),
        ]
        if fallback != "none" {
            Logger(subsystem: "codex.otel", category: "auth_storage")
                .warning("credential storage file fallback completed")
        }
        let names: (String, String)
        switch operation {
        case .refreshPersist:
            names = ("codex.auth_storage.refresh_persist", "codex.auth_storage.refresh_persist.duration")
        case .load, .save, .delete, .cleanup:
            names = ("codex.auth_storage.operation", "codex.auth_storage.duration")
        }
        try? recordGlobalOperation(
            countName: names.0,
            durationName: names.1,
            duration: duration,
            tags: tags
        )
    }
}

/// Records one logical storage operation when the guard is dropped.
public final class StorageTelemetry: @unchecked Sendable {
    private var observation: Observation
    private let started: ContinuousClock.Instant
    private let recorded = OSAllocatedUnfairLock(initialState: false)

    public init(
        credentialKind: CredentialKind,
        mode: StoreMode,
        selectedStore: Store,
        operation: Operation,
        originator: AuthStorageOriginator
    ) {
        observation = Observation(
            credentialKind: credentialKind,
            mode: mode,
            selectedStore: selectedStore,
            actualStore: selectedStore,
            operation: operation,
            secureOutcome: .notAttempted,
            outcome: .notAttempted,
            duration: .zero,
            phase: .policy,
            secureError: "none",
            originator: originator
        )
        started = ContinuousClock.now
    }

    deinit {
        finish()
    }

    public func withPhase(_ phase: StoragePhase) -> StorageTelemetry {
        observation.phase = phase
        return self
    }

    public func recordSecureError(_ error: Error) {
        if let io = error as? IOError {
            switch io.kind {
            case .permissionDenied:
                observation.secureError = "access_denied"
                return
            case .wouldBlock:
                observation.secureError = "locked"
                return
            default:
                break
            }
        }
        observation.secureError = "other"
    }

    public func recordLoadAttempt<T>(store: Store, result: Result<T?, Error>) {
        let outcome: Outcome
        switch result {
        case .success(.some): outcome = .success
        case .success(.none): outcome = .notFound
        case .failure: outcome = .error
        }
        recordAttempt(store: store, outcome: outcome)
    }

    public func recordSaveAttempt(store: Store, succeeded: Bool) {
        recordAttempt(store: store, outcome: succeeded ? .success : .error)
    }

    public func recordDeleteAttempt(store: Store, deleted: Bool?, failed: Bool) {
        let outcome: Outcome
        if failed {
            outcome = .error
        } else if deleted == true {
            outcome = .success
        } else {
            outcome = .notFound
        }
        recordAttempt(store: store, outcome: outcome)
    }

    public func finish() {
        let already = recorded.withLock { value -> Bool in
            if value { return true }
            value = true
            return false
        }
        guard !already, observation.outcome != .notAttempted else { return }
        observation.duration = ContinuousClock.now - started
        observation.record()
    }

    private func recordAttempt(store: Store, outcome: Outcome) {
        observation.actualStore = store
        observation.outcome = outcome
        if store == .directKeyring || store == .secrets {
            observation.secureOutcome = outcome
            if outcome != .error {
                observation.secureError = "none"
            } else if observation.secureError == "none" {
                observation.secureError = "other"
            }
        }
    }
}
