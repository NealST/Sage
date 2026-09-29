//
//  core_test_support.swift
//  CodexCore
//
//  Port of codex-rs/core/src/test_support.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename collides with plugins/test_support.swift. Cross-crate
//  test helpers that do not need Session / login / models manager.
//  ThreadManager factory helpers and offline model catalogs wait.
//

import CodexProtocol
import Foundation

/// Test-only provider that supplies no user instructions.
public struct EmptyUserInstructionsProvider: UserInstructionsProvider {
    public init() {}

    public func loadUserInstructions() async -> LoadedHostInstructions {
        LoadedHostInstructions()
    }
}

public func setDeterministicProcessIds(_ enabled: Bool) {
    setDeterministicProcessIdsForTests(enabled)
}

public enum TestCodexResponsesRequestKind: Equatable, Sendable {
    case turn
    case prewarm
    case websocketConnection
}

public func responsesMetadata(
    installationId: String,
    sessionId: String,
    threadId: String,
    turnId: String?,
    windowId: String,
    sessionSource: SessionSource,
    parentThreadId: ThreadId?,
    requestKind: TestCodexResponsesRequestKind
) -> CodexResponsesMetadata {
    let mappedKind: CodexResponsesRequestKind?
    switch requestKind {
    case .turn: mappedKind = .turn
    case .prewarm: mappedKind = .prewarm
    case .websocketConnection: mappedKind = nil
    }
    var metadata = CodexResponsesMetadata(
        installationId: installationId,
        sessionId: sessionId,
        threadId: threadId,
        windowId: windowId
    )
    metadata.turnId = mappedKind == nil ? nil : turnId
    metadata.requestKind = mappedKind
    metadata.parentThreadId = parentThreadId
    metadata.subagentHeader = subagentHeaderValue(sessionSource)
    metadata.subagentKind = mappedKind == nil ? nil : subagentMetadataKind(sessionSource)
    return metadata
}

public func minimalModelInfo(slug: String = "gpt-5") -> ModelInfo {
    let json = """
    {
      "slug": "\(slug)",
      "display_name": "\(slug)",
      "supported_reasoning_levels": [],
      "shell_type": "unified_exec",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 0,
      "support_verbosity": true,
      "truncation_policy": { "mode": "tokens", "limit": 1000 },
      "experimental_supported_tools": []
    }
    """
    return try! JSONDecoder().decode(ModelInfo.self, from: Data(json.utf8))
}

public func withParentTurn(_ metadata: CodexResponsesMetadata, id: String) -> CodexResponsesMetadata {
    var copy = metadata
    copy.parentTurnId = id
    return copy
}
