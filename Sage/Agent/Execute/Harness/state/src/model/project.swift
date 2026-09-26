//
//  project.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/project.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

public struct ProjectRoot: Codable, Equatable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var roots: [ProjectRoot]
    public var metadata: [String: String]
    public var position: Int64
    public var createdAtMs: Int64
    public var updatedAtMs: Int64
    public var recencyAtMs: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, roots, metadata, position
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case recencyAtMs = "recency_at_ms"
    }

    public init(
        id: String,
        name: String,
        roots: [ProjectRoot],
        metadata: [String: String] = [:],
        position: Int64,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        recencyAtMs: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.roots = roots
        self.metadata = metadata
        self.position = position
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.recencyAtMs = recencyAtMs
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(roots, forKey: .roots)
        // BTreeMap encodes with sorted keys.
        var metadataContainer = container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: .metadata)
        for key in metadata.keys.sorted() {
            try metadataContainer.encode(metadata[key], forKey: JSONCodingKey(key))
        }
        try container.encode(position, forKey: .position)
        try container.encode(createdAtMs, forKey: .createdAtMs)
        try container.encode(updatedAtMs, forKey: .updatedAtMs)
        try container.encodeIfPresent(recencyAtMs, forKey: .recencyAtMs)
    }
}

private struct JSONCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public enum ProjectSortKey: String, Codable, Equatable, Sendable {
    case position
    case recencyAt
}

public struct CreatedProject: Codable, Equatable, Sendable {
    public var project: Project
    public var created: Bool

    public init(project: Project, created: Bool) {
        self.project = project
        self.created = created
    }
}

public struct ProjectsPage: Codable, Equatable, Sendable {
    public var projects: [Project]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case projects
        case nextCursor = "next_cursor"
    }

    public init(projects: [Project], nextCursor: String? = nil) {
        self.projects = projects
        self.nextCursor = nextCursor
    }
}
