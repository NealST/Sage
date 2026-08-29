@testable import Sage
import XCTest

final class PlanStreamAdapterTests: XCTestCase {
    func testProseStreamsImmediately() {
        var adapter = PlanStreamAdapter()
        XCTAssertEqual(adapter.ingest("哈"), "哈")
        XCTAssertEqual(adapter.ingest("哈，今天不错。"), "哈哈，今天不错。")
        XCTAssertEqual(adapter.finish(), .answer("哈哈，今天不错。"))
    }

    func testJSONStaysHidden() {
        var adapter = PlanStreamAdapter()
        XCTAssertNil(adapter.ingest("{"))
        XCTAssertNil(adapter.ingest(#""kind":"act"}"#))
        XCTAssertEqual(adapter.finish(), .envelope(#"{"kind":"act"}"#))
    }

    func testLeadingWhitespaceThenJSON() {
        var adapter = PlanStreamAdapter()
        XCTAssertNil(adapter.ingest("  \n"))
        XCTAssertNil(adapter.ingest(#"{"kind":"observe"}"#))
        XCTAssertEqual(adapter.finish(), .envelope("  \n{\"kind\":\"observe\"}"))
    }

    func testFencedJSONIsEnvelope() {
        var adapter = PlanStreamAdapter()
        XCTAssertNil(adapter.ingest("```json\n{\"kind\":\"act\"}"))
        XCTAssertEqual(
            adapter.finish(),
            .envelope("```json\n{\"kind\":\"act\"}")
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
}
