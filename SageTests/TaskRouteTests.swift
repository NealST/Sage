@testable import Sage
import XCTest

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

    func testBeginNewFactory() {
        let begin = TaskRoute.beginNew(reason: "new topic")
        XCTAssertEqual(begin.action, .beginNew)
        XCTAssertTrue(begin.relatedTaskIDs.isEmpty)
    }

    func testContinuityNeverResumesAPriorTask() async {
        let prior = Self.seededTask(topic: "整理 Downloads")
        let current = Self.seededTask(topic: "写 pre-commit hook")
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: current,
            recentSummaries: [
                TaskSummary(
                    id: prior.id,
                    status: prior.status,
                    projectID: prior.projectID,
                    summary: prior.summary,
                    topic: prior.topic,
                    abstract: prior.abstract,
                    updatedAt: prior.updatedAt
                ),
            ],
            recentProjects: [],
            activeTaskID: current.id
        )
        let related = await ContinuityTaskResolver().route(
            input: "继续整理 Downloads 里的 PDF",
            workspace: workspace
        )
        XCTAssertEqual(related.action, .continueActive)
        XCTAssertEqual(related.relatedTaskIDs, current.relatedTaskIDs)

        let fresh = await ContinuityTaskResolver().route(
            input: "新任务：帮我写一个脚本",
            workspace: workspace
        )
        XCTAssertEqual(fresh.action, .beginNew)
    }

    func testRouterKeepsCurrentTaskWhenTopicsDiverge() async {
        let task = Self.seededTask(topic: "整理 Downloads")
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        let route = await CompositeTaskRouter().route(
            input: "Please write a git pre-commit hook in Python for this repository",
            workspace: workspace
        )
        XCTAssertEqual(route.action, .continueActive)
    }

    func testRouterBeginsNewOnExplicitFreshStart() async {
        let task = Self.seededTask(topic: "整理 Downloads")
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        let route = await CompositeTaskRouter().route(
            input: "新任务：帮我写一个脚本",
            workspace: workspace
        )
        XCTAssertEqual(route.action, .beginNew)
    }

    func testRouterBeginsNewWhenNoActiveTask() async {
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: nil,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: nil
        )
        let route = await CompositeTaskRouter().route(
            input: "Summarize my Downloads folder",
            workspace: workspace
        )
        XCTAssertEqual(route.action, .beginNew)
    }

    func testForkTakesOnlyTheUserInput() {
        let first = AgentEvent(kind: .userInput, content: "old")
        let second = AgentEvent(kind: .assistantResponse, content: "ok")
        let third = AgentEvent(kind: .userInput, content: "new topic")
        let fourth = AgentEvent(kind: .assistantResponse, content: "sure")
        let fork = AgentEventHelpers.forkLastUserInput(
            events: [first, second, third, fourth],
            userEventID: third.id
        )
        XCTAssertEqual(fork?.kept.map(\.id), [first.id, second.id])
        XCTAssertEqual(fork?.moved.id, third.id)
        XCTAssertEqual(fork?.discarded.map(\.id), [fourth.id])
    }

    func testForkRequiresUserEvent() {
        let assistant = AgentEvent(kind: .assistantResponse, content: "ok")
        XCTAssertNil(AgentEventHelpers.forkLastUserInput(events: [assistant], userEventID: assistant.id))
    }

    private static func seededTask(topic: String) -> TaskRecord {
        TaskRecord(
            summary: topic,
            topic: topic,
            abstract: topic,
            events: [
                AgentEvent(kind: .userInput, content: topic),
                AgentEvent(kind: .assistantResponse, content: "Working on it."),
                AgentEvent(kind: .userInput, content: "Keep going"),
                AgentEvent(kind: .assistantResponse, content: "Done."),
            ]
        )
    }
}

final class TopicDriftTests: XCTestCase {
    func testThreadLabelPrefersTopic() {
        XCTAssertEqual(
            TopicDriftDetector.threadLabel(
                topic: "整理 Downloads",
                abstract: "longer abstract that should lose",
                summary: "summary"
            ),
            "整理 Downloads"
        )
    }

    func testThreadLabelFallsBackToClippedAbstract() {
        let label = TopicDriftDetector.threadLabel(
            topic: "  ",
            abstract: "abcdefghijklmnopqrstuvwxyz extra",
            summary: "summary"
        )
        XCTAssertEqual(label, "abcdefghijklmnopqrstuvwx…")
    }

    func testThreadLabelFallsBackToSummary() {
        XCTAssertEqual(
            TopicDriftDetector.threadLabel(topic: nil, abstract: nil, summary: "Nightly inbox"),
            "Nightly inbox"
        )
    }

    func testOfferMessageQuotesTheLabel() {
        let offer = TopicDriftOffer(
            taskID: UUID(),
            triggeringUserEventID: UUID(),
            topicLabel: "整理 Downloads"
        )
        XCTAssertTrue(offer.message.contains("整理 Downloads"))
        XCTAssertTrue(offer.message.contains("\u{201C}"))
    }
}
