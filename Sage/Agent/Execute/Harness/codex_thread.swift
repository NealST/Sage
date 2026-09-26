//
//  codex_thread.swift
//  CodexCore
//
//  Port of codex-rs/core/src/codex_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session, Op submission, and store persistence are not wired. This is the
//  public handle type plus startup metadata.
//

import CodexProtocol
import Foundation

public final class CodexThread: @unchecked Sendable {
    public let threadId: ThreadId
    public let startup: ThreadStartupMetadata

    public init(threadId: ThreadId, startup: ThreadStartupMetadata) {
        self.threadId = threadId
        self.startup = startup
    }
}
