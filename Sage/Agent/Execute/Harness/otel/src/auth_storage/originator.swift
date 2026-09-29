//
//  originator.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/auth_storage/originator.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Task-local `CURRENT` is a thread-local box (no tokio task_local).
//

import Foundation

private enum AuthStorageOriginatorBox {
    @TaskLocal static var current: AuthStorageOriginator?
}

/// A bounded client identity used only by credential-storage telemetry.
public struct AuthStorageOriginator: Equatable, Sendable {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public static func fromClientName(_ name: String) -> AuthStorageOriginator {
        let mapped = name == "Codex Desktop" ? "codex_desktop" : name
        return AuthStorageOriginator(boundedOriginatorTagValue(mapped))
    }

    public static func current() -> AuthStorageOriginator {
        AuthStorageOriginatorBox.current ?? AuthStorageOriginator("none")
    }

    public func asStr() -> String { value }

    public func scope<T>(_ operation: () throws -> T) rethrows -> T {
        try AuthStorageOriginatorBox.$current.withValue(self, operation: operation)
    }

    public func syncScope<T>(_ operation: () throws -> T) rethrows -> T {
        try scope(operation)
    }
}
