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
    func testOffersWhenInputHasNoOverlapWithTopic() {
        let task = seededTask(topic: "整理 Downloads")
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        let userEventID = UUID()
        let offer = TopicDriftDetector.offer(
            input: "Please write a git pre-commit hook in Python for this repository",
            workspace: workspace,
            triggeringUserEventID: userEventID,
            suppressedTaskID: nil
        )
        XCTAssertEqual(offer?.taskID, task.id)
        XCTAssertEqual(offer?.triggeringUserEventID, userEventID)
        XCTAssertEqual(offer?.topicLabel, "整理 Downloads")
        XCTAssertTrue(offer?.message.contains("整理 Downloads") == true)
    }

    func testDoesNotOfferShortFollowUps() {
        let task = seededTask(topic: "整理 Downloads")
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        XCTAssertNil(
            TopicDriftDetector.offer(
                input: "再试一次",
                workspace: workspace,
                triggeringUserEventID: UUID(),
                suppressedTaskID: nil
            )
        )
    }

    func testDoesNotOfferWhenTokensOverlap() {
        let task = seededTask(topic: "整理 Downloads")
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        XCTAssertNil(
            TopicDriftDetector.offer(
                input: "把 Downloads 里的 PDF 再整理一遍到分类文件夹",
                workspace: workspace,
                triggeringUserEventID: UUID(),
                suppressedTaskID: nil
            )
        )
    }

    func testDoesNotOfferWhenSuppressedForThisTask() {
        let task = seededTask(topic: "整理 Downloads")
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        XCTAssertNil(
            TopicDriftDetector.offer(
                input: "Please write a git pre-commit hook in Python for this repository",
                workspace: workspace,
                triggeringUserEventID: UUID(),
                suppressedTaskID: task.id
            )
        )
    }

    func testDoesNotOfferWhenFollowUpMatchesRecentTurns() {
        let task = TaskRecord(
            summary: "整理 Downloads",
            topic: "整理 Downloads",
            abstract: "整理 Downloads",
            events: [
                AgentEvent(kind: .userInput, content: "整理 Downloads"),
                AgentEvent(kind: .assistantResponse, content: "Sorted files by type."),
                AgentEvent(kind: .userInput, content: "Write organize.py to do this next time"),
                AgentEvent(kind: .assistantResponse, content: "Created organize.py with pathlib."),
            ]
        )
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        XCTAssertNil(
            TopicDriftDetector.offer(
                input: "Please add argparse to organize.py so I can choose the folder",
                workspace: workspace,
                triggeringUserEventID: UUID(),
                suppressedTaskID: nil
            )
        )
    }

    func testDoesNotOfferWhenPriorEventsAreShort() {
        let task = TaskRecord(
            summary: "整理 Downloads",
            topic: "整理 Downloads",
            abstract: "整理 Downloads",
            events: [
                AgentEvent(kind: .userInput, content: "整理 Downloads"),
                AgentEvent(kind: .assistantResponse, content: "OK"),
            ]
        )
        let workspace = TaskWorkspaceSnapshot(
            focusedProject: nil,
            activeTask: task,
            recentSummaries: [],
            recentProjects: [],
            activeTaskID: task.id
        )
        XCTAssertNil(
            TopicDriftDetector.offer(
                input: "Please write a git pre-commit hook in Python for this repository",
                workspace: workspace,
                triggeringUserEventID: UUID(),
                suppressedTaskID: nil
            )
        )
    }

    private func seededTask(topic: String) -> TaskRecord {
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
