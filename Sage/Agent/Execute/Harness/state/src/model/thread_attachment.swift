//
//  thread_attachment.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/thread_attachment.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `serde_json::Value` maps to `JSONValue`.
//

import CodexProtocol
import Foundation

/// A bounded attachment durably associated with one thread.
public struct ThreadAttachment: Codable, Equatable, Sendable {
    /// Stable, server-assigned UUIDv7 attachment identity.
    public var id: String
    /// Thread that owns this attachment.
    public var threadId: ThreadId
    /// Client-defined attachment category.
    public var attachmentType: String
    /// Client-defined stable identity within the owning thread and attachment category.
    public var identityKey: String
    /// Bounded, client-defined attachment metadata.
    public var payload: JSONValue
    /// Integer Unix timestamp in seconds when the attachment was attached.
    public var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case attachmentType = "attachment_type"
        case identityKey = "identity_key"
        case payload
        case createdAt = "created_at"
    }

    public init(
        id: String,
        threadId: ThreadId,
        attachmentType: String,
        identityKey: String,
        payload: JSONValue,
        createdAt: Int64
    ) {
        self.id = id
        self.threadId = threadId
        self.attachmentType = attachmentType
        self.identityKey = identityKey
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// Result of attaching one uniquely identified thread attachment.
public enum AddThreadAttachmentOutcome: Codable, Equatable, Sendable {
    /// A new durable attachment was created.
    case created(ThreadAttachment)
    /// The attachment was already attached; its payload and creation time are unchanged.
    case existing(ThreadAttachment)
}

/// Result of removing a thread attachment.
public enum RemoveThreadAttachmentOutcome: Codable, Equatable, Sendable {
    /// An attached attachment was removed.
    case removed(ThreadAttachment)
    /// No attachment with the requested identity was attached.
    case notFound
}

/// One deterministically ordered page of attachments across selected threads.
public struct ThreadAttachmentPage: Codable, Equatable, Sendable {
    /// Attachments ordered by thread identity, creation time, and attachment identity.
    public var attachments: [ThreadAttachment]
    /// Opaque cursor for the next page, or `nil` when the selection is exhausted.
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case attachments
        case nextCursor = "next_cursor"
    }

    public init(attachments: [ThreadAttachment], nextCursor: String? = nil) {
        self.attachments = attachments
        self.nextCursor = nextCursor
    }
}
