//
//  discovery.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/discovery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Discovery walks ConfigLayerStack, plugin manifests, and hook JSON.
//  Those crates are not ported yet; this file keeps the result type.
//

import CodexProtocol
import Foundation

public struct DiscoveredHandlers: Equatable, Sendable {
    public var handlers: [ConfiguredHandler]
    public var warnings: [String]
    public var requiredLoadErrors: [String]

    public init(
        handlers: [ConfiguredHandler] = [],
        warnings: [String] = [],
        requiredLoadErrors: [String] = []
    ) {
        self.handlers = handlers
        self.warnings = warnings
        self.requiredLoadErrors = requiredLoadErrors
    }
}

public func discoverHandlers() throws -> DiscoveredHandlers {
    throw CodexErr.unsupportedOperation(
        "discover_handlers waits on ConfigLayerStack / plugin hook sources"
    )
}
