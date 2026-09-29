//
//  config_rules.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/config_rules.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `HookStateToml` is faithful. `hook_states_from_stack` returns an empty
//  map until ConfigLayerStack is ported.
//

import Foundation

public struct HookStateToml: Equatable, Sendable {
    public var enabled: Bool?
    public var trustedHash: String?

    public init(enabled: Bool? = nil, trustedHash: String? = nil) {
        self.enabled = enabled
        self.trustedHash = trustedHash
    }
}

/// Build effective hook state from config layers that are allowed to override
/// user preferences.
public func hookStatesFromStack() -> [String: HookStateToml] {
    [:]
}
