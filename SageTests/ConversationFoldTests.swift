@testable import Sage
import XCTest

final class ConversationFoldTests: XCTestCase {
    func testNeedsMoreThanTwoUserTurns() {
        XCTAssertNil(ConversationFold.span(in: dialogue(2), existing: nil))
    }

    func testFoldsEverythingBeforeTheLastTwoUserTurns() {
        let events = dialogue(3)
        let span = ConversationFold.span(in: events, existing: nil)
        XCTAssertEqual(span?.fromEventID, events[0].id)
        XCTAssertEqual(span?.throughEventID, events[1].id)
    }

    func testIgnoresSystemInstructionsWhenChoosingASpan() {
        let system = AgentEvent(kind: .systemInstruction, content: "sys")
        let events = [system] + dialogue(3)
        let span = ConversationFold.span(in: events, existing: nil)
        XCTAssertEqual(span?.fromEventID, events[1].id)
        XCTAssertEqual(span?.throughEventID, events[2].id)
    }

    func testIncrementalSpanStartsAfterTheExistingFold() {
        let events = dialogue(4)
        let existing = TaskWorkingMemory.makeSimple(
            foldedFromEventID: events[0].id,
            foldedThroughEventID: events[1].id,
            narrative: "first fold"
        )
        let span = ConversationFold.span(in: events, existing: existing)
        XCTAssertEqual(span?.fromEventID, events[2].id)
        XCTAssertEqual(span?.throughEventID, events[3].id)
    }

    func testReturnsNilWhenTheNewSpanWouldBeTooShort() {
        let events = dialogue(3)
        let existing = TaskWorkingMemory.makeSimple(
            foldedFromEventID: events[0].id,
            foldedThroughEventID: events[1].id,
            narrative: "first fold"
        )
        XCTAssertNil(ConversationFold.span(in: events, existing: existing))
    }

    func testSliceIsInclusiveAndOrdered() {
        let events = dialogue(3)
        let slice = ConversationFold.slice(
            events,
            from: events[1].id,
            through: events[3].id
        )
        XCTAssertEqual(slice.map(\.id), [events[1].id, events[2].id, events[3].id])
        XCTAssertEqual(
            ConversationFold.slice(events, from: events[3].id, through: events[1].id),
            []
        )
    }

    func testShouldKeepSnapshotRespectsDiscardFloor() {
        XCTAssertFalse(ContextCompactor.shouldKeepSnapshot(occupancyIgnoringMemory: 0.64))
        XCTAssertTrue(ContextCompactor.shouldKeepSnapshot(occupancyIgnoringMemory: 0.65))
        XCTAssertTrue(ContextCompactor.shouldKeepSnapshot(occupancyIgnoringMemory: 0.90))
    }

    private func dialogue(_ userTurns: Int) -> [AgentEvent] {
        (0..<userTurns).flatMap { index in
            [
                AgentEvent(kind: .userInput, content: "user-\(index)"),
                AgentEvent(kind: .assistantResponse, content: "assistant-\(index)"),
            ]
        }
    }
}
