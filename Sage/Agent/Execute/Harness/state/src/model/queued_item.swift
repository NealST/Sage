//
//  queued_item.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/queued_item.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx `try_from_row` is omitted; GRDB mapping lands with the runtime store.
//

import CodexProtocol
import Foundation

/// One durable, ordered user submission for a thread.
public struct QueuedUserSubmissionRecord: Codable, Equatable, Sendable {
    public var id: String
    public var threadId: ThreadId
    public var payload: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case payload
    }

    public init(id: String, threadId: ThreadId, payload: String) {
        self.id = id
        self.threadId = threadId
        self.payload = payload
    }
}
