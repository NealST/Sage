//
//  thread_attachments.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/thread_attachments.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Attachment records / outcomes stand in for unported CodexState models.
//  Limits come from codex-rs/state/src/lib.rs. In-memory add/list/remove/copy
//  lives on `InMemoryThreadStore`.
//

import CodexProtocol
import Foundation

/// Maximum serialized size of one persisted thread-attachment payload.
public let MAX_THREAD_ATTACHMENT_PAYLOAD_BYTES = 64 * 1024

/// Maximum byte length of a persisted attachment type.
public let MAX_THREAD_ATTACHMENT_TYPE_BYTES = 256

/// Maximum byte length of a persisted stable attachment identity key.
public let MAX_THREAD_ATTACHMENT_IDENTITY_KEY_BYTES = 256

/// Maximum number of attachments returned in one page.
public let MAX_THREAD_ATTACHMENT_LIST_PAGE_SIZE = 100

/// Maximum number of active attachments retained for one thread.
public let MAX_THREAD_ATTACHMENTS_PER_THREAD = 100

/// A bounded attachment durably associated with one thread.
public struct ThreadAttachment: Codable, Equatable, Sendable {
    public var id: String
    public var threadId: ThreadId
    public var attachmentType: String
    public var identityKey: String
    public var payload: JSONValue
    public var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, payload
        case threadId = "thread_id"
        case attachmentType = "attachment_type"
        case identityKey = "identity_key"
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
    case created(ThreadAttachment)
    case existing(ThreadAttachment)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let attachment = try container.decodeIfPresent(ThreadAttachment.self, forKey: .created) {
            self = .created(attachment)
        } else if let attachment = try container.decodeIfPresent(ThreadAttachment.self, forKey: .existing) {
            self = .existing(attachment)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown AddThreadAttachmentOutcome"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .created(let attachment):
            try container.encode(attachment, forKey: .created)
        case .existing(let attachment):
            try container.encode(attachment, forKey: .existing)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case created = "Created"
        case existing = "Existing"
    }
}

/// Result of removing a thread attachment.
public enum RemoveThreadAttachmentOutcome: Codable, Equatable, Sendable {
    case removed(ThreadAttachment)
    case notFound

    public init(from decoder: any Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self), raw == "NotFound" {
            self = .notFound
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let attachment = try container.decodeIfPresent(ThreadAttachment.self, forKey: .removed) {
            self = .removed(attachment)
        } else if container.contains(.notFound) {
            self = .notFound
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown RemoveThreadAttachmentOutcome"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .removed(let attachment):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(attachment, forKey: .removed)
        case .notFound:
            var container = encoder.singleValueContainer()
            try container.encode("NotFound")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case removed = "Removed"
        case notFound = "NotFound"
    }
}

/// One deterministically ordered page of attachments.
public struct ThreadAttachmentPage: Codable, Equatable, Sendable {
    public var attachments: [ThreadAttachment]
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

/// Parameters for attaching a thread-owned attachment.
public struct AddThreadAttachmentParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var attachmentType: String
    public var identityKey: String
    public var payload: JSONValue

    enum CodingKeys: String, CodingKey {
        case payload
        case threadId = "thread_id"
        case attachmentType = "attachment_type"
        case identityKey = "identity_key"
    }

    public init(
        threadId: ThreadId,
        attachmentType: String,
        identityKey: String,
        payload: JSONValue
    ) {
        self.threadId = threadId
        self.attachmentType = attachmentType
        self.identityKey = identityKey
        self.payload = payload
    }
}

/// Parameters for listing attachments owned by one thread.
public struct ListThreadAttachmentsParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var cursor: String?
    public var limit: Int

    enum CodingKeys: String, CodingKey {
        case cursor, limit
        case threadId = "thread_id"
    }

    public init(threadId: ThreadId, cursor: String? = nil, limit: Int) {
        self.threadId = threadId
        self.cursor = cursor
        self.limit = limit
    }
}

/// Parameters for removing a thread-owned attachment.
public struct RemoveThreadAttachmentParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var attachmentType: String
    public var identityKey: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case attachmentType = "attachment_type"
        case identityKey = "identity_key"
    }

    public init(threadId: ThreadId, attachmentType: String, identityKey: String) {
        self.threadId = threadId
        self.attachmentType = attachmentType
        self.identityKey = identityKey
    }
}
