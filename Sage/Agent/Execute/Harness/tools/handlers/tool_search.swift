//
//  tool_search.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/tool_search.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  BM25 ranking and Session tool-search cache wait for Phase 5. This
//  handler matches deferred tools by substring against registered search
//  info.
//

import CodexCore
import CodexProtocol
import Foundation

struct ToolSearchArgs: Decodable {
    var query: String
    var limit: Int?

    enum CodingKeys: String, CodingKey { case query, limit }
}

struct ToolSearchCandidate: Equatable, Sendable {
    var toolName: ToolName
    var info: ToolSearchInfo
}

struct ToolSearchHandler: CoreToolRuntime {
    var candidates: [ToolSearchCandidate]
    var defaultLimit: Int
    var sources: [ToolSearchSourceInfo]
    var sourceListing: ToolSearchSourceListing

    init(
        candidates: [ToolSearchCandidate] = [],
        defaultLimit: Int = 8,
        sources: [ToolSearchSourceInfo] = [],
        sourceListing: ToolSearchSourceListing = .include
    ) {
        self.candidates = candidates
        self.defaultLimit = defaultLimit
        self.sources = sources
        self.sourceListing = sourceListing
    }

    func toolName() -> ToolName { ToolName(plain: TOOL_SEARCH_TOOL_NAME) }
    func spec() -> ToolSpec {
        createToolSearchTool(
            searchableSources: sources,
            defaultLimit: defaultLimit,
            sourceListing: sourceListing
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let query: String
        switch invocation.payload {
        case .function(let arguments):
            let args: ToolSearchArgs = try parseArguments(arguments)
            query = args.query
        case .toolSearch(let arguments):
            query = arguments.query
        default:
            throw FunctionCallError.respondToModel(
                "tool_search handler received unsupported payload"
            )
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty {
            throw FunctionCallError.respondToModel("tool_search query must not be empty")
        }
        let limit: Int
        if case .function(let arguments) = invocation.payload,
           let args = try? JSONDecoder().decode(ToolSearchArgs.self, from: Data(arguments.utf8)),
           let requested = args.limit {
            limit = max(1, requested)
        } else {
            limit = defaultLimit
        }
        let matches = candidates.filter { candidate in
            let haystack = (
                flatToolName(candidate.toolName) + " " +
                candidate.info.description + " " +
                candidate.info.keywords.joined(separator: " ")
            ).lowercased()
            return haystack.contains(needle)
        }.prefix(limit)
        let names = matches.map { flatToolName($0.toolName) }
        let body = names.isEmpty
            ? "No matching deferred tools."
            : "Matching tools:\n" + names.map { "- \($0)" }.joined(separator: "\n")
        return boxedToolOutput(FunctionToolOutput.fromText(body, success: true))
    }
}
