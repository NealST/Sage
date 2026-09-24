//
//  assistant_text.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/assistant_text.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

public struct AssistantTextChunk {
    public var visibleText: String
    public var citations: [String]
    public var planSegments: [ProposedPlanSegment]

    /// `Default::default`.
    public init() {
        visibleText = ""
        citations = []
        planSegments = []
    }

    public init(
        visibleText: String,
        citations: [String],
        planSegments: [ProposedPlanSegment]
    ) {
        self.visibleText = visibleText
        self.citations = citations
        self.planSegments = planSegments
    }

    public var isEmpty: Bool {
        visibleText.isEmpty && citations.isEmpty && planSegments.isEmpty
    }
}

extension AssistantTextChunk: Equatable {}

/// Parses assistant text streaming markup in one pass:
/// - strips `<oai-mem-citation>` tags and extracts citation payloads
/// - in plan mode, also strips `<proposed_plan>` blocks and emits plan
///   segments
public final class AssistantTextStreamParser {
    private let planMode: Bool
    private let citations = CitationStreamParser()
    private let plan = ProposedPlanParser()

    public init(planMode: Bool) {
        self.planMode = planMode
    }

    /// `Default::default` (plan mode off).
    public convenience init() {
        self.init(planMode: false)
    }

    public func pushStr(_ chunk: String) -> AssistantTextChunk {
        let citationChunk = citations.pushStr(chunk)
        var out = parseVisibleText(citationChunk.visibleText)
        out.citations = citationChunk.extracted
        return out
    }

    public func finish() -> AssistantTextChunk {
        let citationChunk = citations.finish()
        var out = parseVisibleText(citationChunk.visibleText)
        if planMode {
            let tail = plan.finish()
            if !tail.isEmpty {
                out.visibleText += tail.visibleText
                out.planSegments.append(contentsOf: tail.extracted)
            }
        }
        out.citations = citationChunk.extracted
        return out
    }

    private func parseVisibleText(_ visibleText: String) -> AssistantTextChunk {
        if !planMode {
            return AssistantTextChunk(visibleText: visibleText, citations: [], planSegments: [])
        }
        let planChunk = plan.pushStr(visibleText)
        return AssistantTextChunk(
            visibleText: planChunk.visibleText,
            citations: [],
            planSegments: planChunk.extracted
        )
    }
}
