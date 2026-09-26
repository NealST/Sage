//
//  thread_sections.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/thread_sections.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `ThreadSection` / appearance stand in for unported CodexState models.
//  Pinned-section constants come from codex-rs/state/src/lib.rs.
//  In-memory catalog + `move_thread_to_section` live on `InMemoryThreadStore`.
//

import Foundation

/// Stable UUIDv7 identifying the built-in pinned thread section.
public let PINNED_THREAD_SECTION_ID = "01984de2-8f74-7c91-a3b2-5c5e937cf318"

/// User-facing name of the built-in pinned thread section.
public let PINNED_THREAD_SECTION_NAME = "Pinned"

/// Visual presentation metadata owned by a thread section.
public struct ThreadSectionAppearance: Codable, Equatable, Sendable {
    public var icon: String?
    public var color: String?

    public init(icon: String? = nil, color: String? = nil) {
        self.icon = icon
        self.color = color
    }
}

/// An independently persisted thread section and its user-facing name.
public struct ThreadSection: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var appearance: ThreadSectionAppearance?

    public init(id: String, name: String, appearance: ThreadSectionAppearance? = nil) {
        self.id = id
        self.name = name
        self.appearance = appearance
    }
}

/// Alias matching the Rust `StoredThreadSection` export.
public typealias StoredThreadSection = ThreadSection

/// Parameters for listing independently persisted thread sections.
public struct ListThreadSectionsParams: Codable, Equatable, Sendable {
    public var cursor: String?
    public var limit: Int

    public init(cursor: String? = nil, limit: Int) {
        self.cursor = cursor
        self.limit = limit
    }
}

/// Parameters for creating a thread section.
public struct CreateThreadSectionParams: Codable, Equatable, Sendable {
    public var name: String
    public var appearance: ThreadSectionAppearance?

    public init(name: String, appearance: ThreadSectionAppearance? = nil) {
        self.name = name
        self.appearance = appearance
    }
}

/// Parameters for renaming a thread section.
public struct RenameThreadSectionParams: Codable, Equatable, Sendable {
    public var sectionId: String
    public var name: String
    public var appearance: ClearableField<ThreadSectionAppearance>

    enum CodingKeys: String, CodingKey {
        case name
        case sectionId = "section_id"
        case appearance
    }

    public init(
        sectionId: String,
        name: String,
        appearance: ClearableField<ThreadSectionAppearance> = nil
    ) {
        self.sectionId = sectionId
        self.name = name
        self.appearance = appearance
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sectionId = try container.decode(String.self, forKey: .sectionId)
        name = try container.decode(String.self, forKey: .name)
        appearance = try decodeClearable(container, forKey: .appearance)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sectionId, forKey: .sectionId)
        try container.encode(name, forKey: .name)
        try encodeClearable(appearance, forKey: .appearance, into: &container)
    }
}

/// Parameters for deleting a thread section.
public struct DeleteThreadSectionParams: Codable, Equatable, Sendable {
    public var sectionId: String

    enum CodingKeys: String, CodingKey { case sectionId = "section_id" }

    public init(sectionId: String) {
        self.sectionId = sectionId
    }
}

/// A cursor-paginated page of independently persisted thread sections.
public struct StoredThreadSectionsPage: Codable, Equatable, Sendable {
    public var sections: [StoredThreadSection]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case sections
        case nextCursor = "next_cursor"
    }

    public init(sections: [StoredThreadSection], nextCursor: String? = nil) {
        self.sections = sections
        self.nextCursor = nextCursor
    }
}
