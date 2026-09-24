//
//  assistant_text_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/stream-parser/src/assistant_text.rs #[cfg(test)]
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation
import XCTest
@testable import CodexUtils

final class AssistantTextStreamParserTests: XCTestCase {

    /// `parses_citations_across_seed_and_delta_boundaries`.
    func testParsesCitationsAcrossSeedAndDeltaBoundaries() {
        let parser = AssistantTextStreamParser(planMode: false)

        let seeded = parser.pushStr("hello <oai-mem-citation>doc")
        let parsed = parser.pushStr("1</oai-mem-citation> world")
        let tail = parser.finish()

        XCTAssertEqual(seeded.visibleText, "hello ")
        XCTAssertEqual(seeded.citations, [])
        XCTAssertEqual(parsed.visibleText, " world")
        XCTAssertEqual(parsed.citations, ["doc1"])
        XCTAssertEqual(tail.visibleText, "")
        XCTAssertEqual(tail.citations, [])
    }

    /// `parses_plan_segments_after_citation_stripping`.
    func testParsesPlanSegmentsAfterCitationStripping() {
        let parser = AssistantTextStreamParser(planMode: true)

        let seeded = parser.pushStr("Intro\n<proposed")
        let parsed = parser.pushStr("_plan>\n- step <oai-mem-citation>doc</oai-mem-citation>\n")
        let tail = parser.pushStr("</proposed_plan>\nOutro")
        let finish = parser.finish()

        XCTAssertEqual(seeded.visibleText, "Intro\n")
        XCTAssertEqual(seeded.planSegments, [.normal("Intro\n")])
        XCTAssertEqual(parsed.visibleText, "")
        XCTAssertEqual(parsed.citations, ["doc"])
        XCTAssertEqual(
            parsed.planSegments,
            [
                .proposedPlanStart,
                .proposedPlanDelta("- step \n"),
            ]
        )
        XCTAssertEqual(tail.visibleText, "Outro")
        XCTAssertEqual(
            tail.planSegments,
            [
                .proposedPlanEnd,
                .normal("Outro"),
            ]
        )
        XCTAssertTrue(finish.isEmpty)
    }
}
