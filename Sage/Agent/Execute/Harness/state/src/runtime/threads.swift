//
//  threads.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/threads.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Listing / upsert SQL is deferred with the rest of threads.rs. This file
//  keeps `ThreadFilterOptions` so `StateRuntime` callers can name the type.
//

import Foundation

/// Filters applied when listing threads. Nested optionals match upstream:
/// `nil` = do not filter, `.some(nil)` = unsectioned / unassigned only.
public struct ThreadFilterOptions: Equatable, Sendable {
    public var archivedOnly: Bool
    public var allowedSources: [String]
    public var modelProviders: [String]?
    public var cwdFilters: [String]?
    public var section: String??
    public var projectId: String??
    public var anchor: Anchor?
    public var sortKey: SortKey
    public var sortDirection: SortDirection
    public var searchTerm: String?

    public init(
        archivedOnly: Bool = false,
        allowedSources: [String] = [],
        modelProviders: [String]? = nil,
        cwdFilters: [String]? = nil,
        section: String?? = nil,
        projectId: String?? = nil,
        anchor: Anchor? = nil,
        sortKey: SortKey = .recencyAt,
        sortDirection: SortDirection = .desc,
        searchTerm: String? = nil
    ) {
        self.archivedOnly = archivedOnly
        self.allowedSources = allowedSources
        self.modelProviders = modelProviders
        self.cwdFilters = cwdFilters
        self.section = section
        self.projectId = projectId
        self.anchor = anchor
        self.sortKey = sortKey
        self.sortDirection = sortDirection
        self.searchTerm = searchTerm
    }
}
