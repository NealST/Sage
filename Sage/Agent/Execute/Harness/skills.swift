//
//  skills.swift
//  CodexCore
//
//  Port of codex-rs/core/src/skills.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Skill load / emit paths close over Config, Session, TurnContext,
//  analytics, and the skills crate. Types that do not need those
//  dependencies are kept; the emit functions throw.
//

import CodexProtocol
import Foundation
import os

/// Deduplicates implicit skill invocations observed on one turn.
public struct ImplicitSkillInvocations: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<String>())

    public init() {}

    public func insert(_ key: String) -> Bool {
        lock.withLock { seen in
            seen.insert(key).inserted
        }
    }
}

public func skillsLoadInputFromConfig() throws -> Never {
    throw CodexErr.unsupportedOperation(
        "skills_load_input_from_config waits on Config / PluginSkillRoot"
    )
}

public func emitExplicitSkillInvocations() async throws {
    throw CodexErr.unsupportedOperation(
        "emit_explicit_skill_invocations waits on Session / TurnContext / skills crate"
    )
}

public func maybeEmitImplicitSkillInvocation() async throws {
    throw CodexErr.unsupportedOperation(
        "maybe_emit_implicit_skill_invocation waits on Session / TurnContext / skills crate"
    )
}
