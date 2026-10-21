@testable import Sage
import XCTest

final class PlanStreamAdapterTests: XCTestCase {
    func testProseStreamsImmediately() {
        var adapter = PlanStreamAdapter()
        XCTAssertEqual(adapter.ingest("哈"), "哈")
        XCTAssertEqual(adapter.ingest("哈，今天不错。"), "哈哈，今天不错。")
        XCTAssertFalse(adapter.isEnvelope)
        XCTAssertEqual(adapter.finish(), .answer("哈哈，今天不错。"))
    }

    func testJSONStaysHidden() {
        var adapter = PlanStreamAdapter()
        XCTAssertFalse(adapter.isEnvelope)
        XCTAssertNil(adapter.ingest("{"))
        XCTAssertTrue(adapter.isReservingWorkPlan)
        XCTAssertNil(adapter.ingest(#""kind":"act"}"#))
        XCTAssertTrue(adapter.isEnvelope)
        XCTAssertEqual(adapter.finish(), .envelope(raw: #"{"kind":"act"}"#, visible: ""))
    }

    func testLeadingWhitespaceThenJSON() {
        var adapter = PlanStreamAdapter()
        XCTAssertNil(adapter.ingest("  \n"))
        XCTAssertNil(adapter.ingest(#"{"kind":"observe"}"#))
        XCTAssertEqual(
            adapter.finish(),
            .envelope(raw: "  \n{\"kind\":\"observe\"}", visible: "")
        )
    }

    func testFencedJSONIsEnvelope() {
        var adapter = PlanStreamAdapter()
        XCTAssertNil(adapter.ingest("```json\n{\"kind\":\"act\"}"))
        XCTAssertTrue(adapter.isEnvelope)
        XCTAssertEqual(
            adapter.finish(),
            .envelope(raw: "```json\n{\"kind\":\"act\"}", visible: "")
        )
    }

    func testFencedSwiftIsAnswer() {
        var adapter = PlanStreamAdapter()
        let chunk = "```swift\nlet x = 1"
        XCTAssertEqual(adapter.ingest(chunk), chunk)
        XCTAssertEqual(adapter.finish(), .answer(chunk))
    }

    func testParsePlainAnswer() {
        let plan = PlanAgent.parsePlain("哈哈，今天也挺好的。")
        XCTAssertEqual(plan?.kind, .answer)
        XCTAssertEqual(plan?.reply, "哈哈，今天也挺好的。")
        XCTAssertEqual(plan?.directReply, "哈哈，今天也挺好的。")
        XCTAssertNotEqual(plan?.requiresConfirmation, true)
    }

    func testParsePlainRejectsJSON() {
        XCTAssertNil(PlanAgent.parsePlain(#"{"kind":"act","intent":"改"}"#))
    }

    func testProseIsNotEnvelope() {
        var adapter = PlanStreamAdapter()
        _ = adapter.ingest("哈")
        XCTAssertFalse(adapter.isEnvelope)
    }

    func testLeadingWhitespaceIsNotEnvelopeUntilJSON() {
        var adapter = PlanStreamAdapter()
        XCTAssertNil(adapter.ingest("  \n"))
        XCTAssertFalse(adapter.isEnvelope)
        XCTAssertFalse(adapter.isReservingWorkPlan)
        XCTAssertNil(adapter.ingest("{"))
        XCTAssertTrue(adapter.isReservingWorkPlan)
        XCTAssertNil(adapter.ingest(#""kind":"observe"}"#))
        XCTAssertTrue(adapter.isEnvelope)
    }

    func testPreambleStreamsThenJSONReservesCard() {
        var adapter = PlanStreamAdapter()
        XCTAssertEqual(adapter.ingest("好的\n"), "好的\n")
        XCTAssertFalse(adapter.isEnvelope)
        XCTAssertFalse(adapter.isReservingWorkPlan)
        XCTAssertEqual(adapter.ingest("{"), "好的")
        XCTAssertTrue(adapter.isReservingWorkPlan)
        XCTAssertEqual(adapter.ingest(#""kind":"act","intent":"改"}"#), "好的")
        XCTAssertTrue(adapter.isEnvelope)
        XCTAssertEqual(
            adapter.finish(),
            .envelope(raw: "好的\n{\"kind\":\"act\",\"intent\":\"改\"}", visible: "好的")
        )
    }

    func testProseThenInlinePlanJSONSplits() {
        var adapter = PlanStreamAdapter()
        XCTAssertEqual(adapter.ingest("好的，"), "好的，")
        let json = #"{"kind":"act","intent":"改"}"#
        XCTAssertEqual(adapter.ingest(json), "好的，")
        XCTAssertTrue(adapter.isEnvelope)
        XCTAssertEqual(
            adapter.finish(),
            .envelope(raw: "好的，" + json, visible: "好的，")
        )
    }
}
