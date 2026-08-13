import XCTest
@testable import Sage

final class TaskRouteTests: XCTestCase {
    func testContinueActiveFactory() {
        let id = UUID()
        let route = TaskRoute.continueActive(
            relatedTaskIDs: [id],
            confidence: 0.9,
            reason: "same topic",
            userVisibleHint: "Continuing"
        )
        XCTAssertEqual(route.action, .continueActive)
        XCTAssertEqual(route.relatedTaskIDs, [id])
        XCTAssertEqual(route.confidence, 0.9)
        XCTAssertEqual(route.userVisibleHint, "Continuing")
        XCTAssertEqual(route.eventContext.relatedTaskIDs, [id])
    }

    func testBeginNewAndResumeFactories() {
        let id = UUID()
        let begin = TaskRoute.beginNew(reason: "new topic")
        XCTAssertEqual(begin.action, .beginNew)
        XCTAssertTrue(begin.relatedTaskIDs.isEmpty)

        let resume = TaskRoute.resume(
            id,
            relatedTaskIDs: [id],
            confidence: 0.8,
            reason: "prior task",
            userVisibleHint: nil
        )
        XCTAssertEqual(resume.action, .resumeTask(id))
    }
}
