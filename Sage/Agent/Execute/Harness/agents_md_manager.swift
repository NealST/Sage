//
//  agents_md_manager.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agents_md_manager.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Snapshot ownership, refresh serialization, and thread-instruction size
//  checks are faithful. `refresh` still waits on Config /
//  TurnEnvironmentSnapshot; callers can apply a preloaded snapshot.
//

import CodexProtocol
import CodexUtils
import Foundation

/// Subagents inherit applied snapshots, plus thread providers that opt into sharing.
public struct SessionInstructions: Sendable {
    public var user: Instructions?
    public var thread: Instructions?
    public var userProvider: (any UserInstructionsProvider)?
    public var threadProvider: (any ThreadInstructionsProvider)?

    public init(
        user: Instructions? = nil,
        thread: Instructions? = nil,
        userProvider: (any UserInstructionsProvider)? = nil,
        threadProvider: (any ThreadInstructionsProvider)? = nil
    ) {
        self.user = user
        self.thread = thread
        self.userProvider = userProvider
        self.threadProvider = threadProvider
    }
}

public struct LoadedHostInstructions: Sendable {
    public var instructions: Instructions?
    public var warnings: [String]

    public init(instructions: Instructions? = nil, warnings: [String] = []) {
        self.instructions = instructions
        self.warnings = warnings
    }
}

public protocol UserInstructionsProvider: Sendable {
    func loadUserInstructions() async -> LoadedHostInstructions
}

public protocol ThreadInstructionsProvider: Sendable {
    func loadThreadInstructions() async -> LoadedHostInstructions
    func shareWithSubagents() -> Bool
}

/// Owns instruction sources, refresh serialization, and the applied snapshot.
public actor AgentsMdManager {
    private var instructions: SessionInstructions
    private var cache = AgentsMdCache()
    private var refreshing = false

    public init(instructions: SessionInstructions = SessionInstructions()) {
        self.instructions = SessionInstructions(
            user: normalizeInstructions(instructions.user),
            thread: normalizeInstructions(instructions.thread),
            userProvider: instructions.userProvider,
            threadProvider: instructions.threadProvider
        )
    }

    /// Resolves and validates one coherent snapshot for startup or a request boundary.
    public func refresh() async -> (Result<LoadedAgentsMd?, CodexErr>, [String]) {
        (
            .failure(
                CodexErr.unsupportedOperation(
                    "AgentsMdManager.refresh waits on Config / TurnEnvironmentSnapshot"
                )
            ),
            []
        )
    }

    /// Applies a preloaded snapshot after validating thread-instruction size.
    public func applyLoaded(
        _ loaded: LoadedAgentsMd?,
        user: Instructions?,
        thread: Instructions?
    ) throws -> LoadedAgentsMd? {
        if let thread, thread.text.utf8.count > 0 {
            try validateThreadInstructionSize(thread.text.utf8.count)
        }
        let applied = (loaded ?? LoadedAgentsMd())
            .withInstructions(userInstructions: user, threadInstructions: thread)
        instructions.user = normalizeInstructions(user)
        instructions.thread = normalizeInstructions(thread)
        cache.loaded = applied
        return applied
    }

    public func getLoaded() -> LoadedAgentsMd? {
        cache.loaded
    }

    public func inheritedInstructions() -> SessionInstructions {
        SessionInstructions(
            user: instructions.user,
            thread: instructions.thread,
            threadProvider: instructions.threadProvider.flatMap { provider in
                provider.shareWithSubagents() ? provider : nil
            }
        )
    }
}

struct AgentsMdCache {
    var loaded: LoadedAgentsMd?
}

let MAX_THREAD_INSTRUCTIONS_TOKENS: Int = 10_000

func validateThreadInstructionSize(_ bytes: Int) throws {
    if bytes > approxBytesForTokens(MAX_THREAD_INSTRUCTIONS_TOKENS) {
        let estimatedTokens = approxTokensFromByteCount(bytes)
        throw CodexErr.invalidRequest(
            "thread instructions exceed the limit of \(MAX_THREAD_INSTRUCTIONS_TOKENS) estimated tokens (\(estimatedTokens) estimated tokens provided)"
        )
    }
}

func normalizeInstructions(_ instructions: Instructions?) -> Instructions? {
    instructions.flatMap { value in
        value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}
