//
//  proposed_plan_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/stream-parser/src/proposed_plan.rs #[cfg(test)]
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation
import XCTest
@testable import CodexUtils

final class ProposedPlanParserTests: XCTestCase {

    private func collectChunks<P: StreamTextParser>(
        _ parser: P,
        _ chunks: [String]
    ) -> StreamTextChunk<P.Extracted> {
        var all = StreamTextChunk<P.Extracted>()
        for chunk in chunks {
            let next = parser.pushStr(chunk)
            all.visibleText += next.visibleText
            all.extracted.append(contentsOf: next.extracted)
        }
        let tail = parser.finish()
        all.visibleText += tail.visibleText
        all.extracted.append(contentsOf: tail.extracted)
        return all
    }

    /// `streams_proposed_plan_segments_and_visible_text`.
    func testStreamsProposedPlanSegmentsAndVisibleText() {
        let parser = ProposedPlanParser()
        let out = collectChunks(parser, [
            "Intro text\n<prop",
            "osed_plan>\n- step 1\n",
            "</proposed_plan>\nOutro",
        ])

        XCTAssertEqual(out.visibleText, "Intro text\nOutro")
        XCTAssertEqual(
            out.extracted,
            [
                .normal("Intro text\n"),
                .proposedPlanStart,
                .proposedPlanDelta("- step 1\n"),
                .proposedPlanEnd,
                .normal("Outro"),
            ]
        )
    }

    /// `preserves_non_tag_lines`.
    func testPreservesNonTagLines() {
        let parser = ProposedPlanParser()
        let out = collectChunks(parser, ["  <proposed_plan> extra\n"])

        XCTAssertEqual(out.visibleText, "  <proposed_plan> extra\n")
        XCTAssertEqual(out.extracted, [.normal("  <proposed_plan> extra\n")])
    }

    /// `closes_unterminated_plan_block_on_finish`.
    func testClosesUnterminatedPlanBlockOnFinish() {
        let parser = ProposedPlanParser()
        let out = collectChunks(parser, ["<proposed_plan>\n- step 1\n"])

        XCTAssertEqual(out.visibleText, "")
        XCTAssertEqual(
            out.extracted,
            [
                .proposedPlanStart,
                .proposedPlanDelta("- step 1\n"),
                .proposedPlanEnd,
            ]
        )
    }

    /// `strips_proposed_plan_blocks_from_text`.
    func testStripsProposedPlanBlocksFromText() {
        let text = "before\n<proposed_plan>\n- step\n</proposed_plan>\nafter"
        XCTAssertEqual(stripProposedPlanBlocks(text), "before\nafter")
    }

    /// `extracts_proposed_plan_text`.
    func testExtractsProposedPlanText() {
        let text = "before\n<proposed_plan>\n- step\n</proposed_plan>\nafter"
        XCTAssertEqual(extractProposedPlanText(text), "- step\n")
    }
}
