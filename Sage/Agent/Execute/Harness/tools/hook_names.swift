//
//  hook_names.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/hook_names.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

struct HookToolName: Equatable, Sendable {
    private var storedName: String
    private var storedAliases: [String]

    init(_ name: String, matcherAliases: [String] = []) {
        storedName = name
        storedAliases = matcherAliases
    }

    static func applyPatch() -> HookToolName {
        HookToolName("apply_patch", matcherAliases: ["Write", "Edit"])
    }

    static func spawnAgent() -> HookToolName {
        HookToolName("spawn_agent", matcherAliases: ["Agent"])
    }

    static func bash() -> HookToolName {
        HookToolName("Bash")
    }

    func name() -> String { storedName }
    func matcherAliases() -> [String] { storedAliases }
}
