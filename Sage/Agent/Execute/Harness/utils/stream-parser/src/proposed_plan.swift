//
//  proposed_plan.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/proposed_plan.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

private let openTag = "<proposed_plan>"
private let closeTag = "</proposed_plan>"

private enum PlanTag {
    case proposedPlan
}

public enum ProposedPlanSegment {
    case normal(String)
    case proposedPlanStart
    case proposedPlanDelta(String)
    case proposedPlanEnd
}

extension ProposedPlanSegment: Equatable {}

/// Parser for `<proposed_plan>` blocks emitted in plan mode.
///
/// Implements `StreamTextParser` so callers can consume:
/// - `visibleText`: normal assistant text with plan blocks removed
/// - `extracted`: ordered plan segments (includes `normal(...)` segments for
///   ordering fidelity)
public final class ProposedPlanParser {
    private let parser: TaggedLineParser<PlanTag>

    public init() {
        parser = TaggedLineParser(specs: [TagSpec(
            open: openTag,
            close: closeTag,
            tag: .proposedPlan
        )])
    }
}

extension ProposedPlanParser: StreamTextParser {
    public func pushStr(_ chunk: String) -> StreamTextChunk<ProposedPlanSegment> {
        mapSegments(parser.parse(chunk))
    }

    public func finish() -> StreamTextChunk<ProposedPlanSegment> {
        mapSegments(parser.finish())
    }
}

private func mapSegments(
    _ segments: [TaggedLineSegment<PlanTag>]
) -> StreamTextChunk<ProposedPlanSegment> {
    var out = StreamTextChunk<ProposedPlanSegment>()
    for segment in segments {
        let mapped: ProposedPlanSegment = switch segment {
        case .normal(let text):
            .normal(text)
        case .tagStart(.proposedPlan):
            .proposedPlanStart
        case .tagDelta(.proposedPlan, let text):
            .proposedPlanDelta(text)
        case .tagEnd(.proposedPlan):
            .proposedPlanEnd
        }
        if case .normal(let text) = mapped {
            out.visibleText += text
        }
        out.extracted.append(mapped)
    }
    return out
}

public func stripProposedPlanBlocks(_ text: String) -> String {
    let parser = ProposedPlanParser()
    var out = parser.pushStr(text).visibleText
    out += parser.finish().visibleText
    return out
}

public func extractProposedPlanText(_ text: String) -> String? {
    let parser = ProposedPlanParser()
    var planText = ""
    var sawPlanBlock = false
    for segment in parser.pushStr(text).extracted + parser.finish().extracted {
        switch segment {
        case .proposedPlanStart:
            sawPlanBlock = true
            planText = ""
        case .proposedPlanDelta(let delta):
            planText += delta
        case .proposedPlanEnd, .normal:
            break
        }
    }
    return sawPlanBlock ? planText : nil
}
