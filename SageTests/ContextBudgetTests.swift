@testable import Sage
import XCTest

final class ContextBudgetTests: XCTestCase {
    func testCapSkillContentLeavesShortPayloadAlone() {
        let content = "<skill_content name=\"x\">hello</skill_content>"
        XCTAssertEqual(ContextBudget.capSkillContent(content, skillName: "x"), content)
    }

    func testCapSkillContentTruncatesOversizedPayload() {
        let huge = String(repeating: "a", count: ContextBudget.maxSkillContentCharacters + 50)
        let capped = ContextBudget.capSkillContent(huge, skillName: "big")
        XCTAssertNotEqual(capped, huge)
        XCTAssertTrue(capped.contains("load_skill_resource"))
        XCTAssertTrue(capped.contains("big"))
        XCTAssertTrue(capped.contains("truncated"))
    }

    func testSelectKeepsProtectedEvents() {
        let protected = AgentEvent(
            kind: .userInput,
            content: "skill body",
            protected: true
        )
        let user = AgentEvent(kind: .userInput, content: "hi")
        let selected = ContextBudget.select(from: [protected, user])
        XCTAssertTrue(selected.contains(where: \.protected))
        XCTAssertTrue(selected.contains { !$0.protected && $0.content == "hi" })
    }

    func testMiddleOutKeepsHeadAndTail() {
        let text = String(repeating: "H", count: 80) + String(repeating: "T", count: 120)
        let clipped = ContextBudget.middleOut(text, maxUTF8Bytes: 80)
        XCTAssertTrue(clipped.contains("middle omitted"))
        XCTAssertTrue(clipped.hasPrefix("H"))
        XCTAssertTrue(clipped.hasSuffix("T"))
        XCTAssertLessThanOrEqual(clipped.utf8.count, 80)
    }

    func testWindowFollowsModelFamily() {
        XCTAssertEqual(PromptBudget.windowTokens(forModel: "gpt-4.1-mini"), 1_000_000)
        XCTAssertEqual(PromptBudget.windowTokens(forModel: "claude-sonnet-4"), 200_000)
        XCTAssertEqual(PromptBudget.windowTokens(forModel: "gpt-4o-mini"), 128_000)
    }

    func testCurrentUserSurvivesWhenHistoryIsDropped() {
        let budget = PromptBudget(windowTokens: 80, reservedOutputTokens: 8, reservedToolTokens: 0)
        var events: [AgentEvent] = []
        for index in 0..<12 {
            events.append(AgentEvent(kind: .userInput, content: String(repeating: "old-\(index) ", count: 40)))
            events.append(AgentEvent(kind: .assistantResponse, content: String(repeating: "reply-\(index) ", count: 40)))
        }
        let current = AgentEvent(kind: .userInput, content: "CURRENT-TURN")
        events.append(current)

        let selected = ContextBudget.select(from: events, budget: budget)
        XCTAssertTrue(selected.contains { $0.id == current.id })
        XCTAssertTrue(selected.contains { $0.content.contains("CURRENT-TURN") })
        XCTAssertLessThan(selected.count, events.count)
    }

    func testToolResultUsesMiddleOutUnderHalfWindowCap() {
        let budget = PromptBudget(windowTokens: 200, reservedOutputTokens: 20, reservedToolTokens: 0)
        let user = AgentEvent(kind: .userInput, content: "run it")
        let callID = "call-1"
        let assistant = AgentEvent(
            kind: .assistantResponse,
            content: "",
            toolCalls: [ToolCallRecord(id: callID, name: "run_shell_command", argumentsJSON: "{}")]
        )
        let huge = String(repeating: "HEAD", count: 80) + String(repeating: "TAIL", count: 80)
        let tool = AgentEvent(kind: .toolResult, content: huge, toolCallID: callID)
        let selected = ContextBudget.select(from: [user, assistant, tool], budget: budget)
        let result = selected.first { $0.kind == .toolResult }
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.content.contains("tool result compacted"), true)
        XCTAssertLessThan(result?.content.utf8.count ?? .max, huge.utf8.count)
        XCTAssertTrue(selected.contains { $0.id == user.id })
    }

    func testRelatedDialogueDropsBeforeCurrentUser() {
        let budget = PromptBudget(windowTokens: 120, reservedOutputTokens: 12, reservedToolTokens: 0)
        let current = AgentEvent(kind: .userInput, content: "please continue")
        let snippets = [
            RelatedTaskContextSnippet(
                id: UUID(),
                projectID: nil,
                topic: "Prior cleanup",
                summary: "cleanup",
                abstract: "Tidy the downloads folder",
                recentDialogue: [
                    RelatedDialogueLine(kind: .user, content: String(repeating: "related-user ", count: 80)),
                    RelatedDialogueLine(kind: .assistant, content: String(repeating: "related-asst ", count: 80)),
                ]
            ),
        ]
        let assembly = ContextBudget.assemble(
            PromptLayout(
                budget: budget,
                baseInstructions: "You are Sage.",
                relatedSnippets: snippets,
                events: [current]
            )
        )
        let system = assembly.events.first { $0.kind == .systemInstruction }?.content ?? ""
        XCTAssertTrue(assembly.events.contains { $0.id == current.id })
        XCTAssertFalse(system.contains("related-user"))
    }

    func testWorkingMemoryReplacesFoldedEvents() {
        let first = AgentEvent(kind: .userInput, content: "clean downloads")
        let second = AgentEvent(kind: .assistantResponse, content: "listed files")
        let current = AgentEvent(kind: .userInput, content: "delete the installers")
        let memory = TaskWorkingMemory.makeStructured(
            foldedFromEventID: first.id,
            foldedThroughEventID: second.id,
            overview: "Clean Downloads"
        )
        let assembly = ContextBudget.assemble(
            PromptLayout(
                budget: .default,
                baseInstructions: "You are Sage.",
                workingMemory: memory,
                events: [first, second, current]
            )
        )
        let ids = Set(assembly.events.map(\.id))
        XCTAssertFalse(ids.contains(first.id))
        XCTAssertFalse(ids.contains(second.id))
        XCTAssertTrue(ids.contains(current.id))
        let system = assembly.events.first { $0.kind == .systemInstruction }?.content ?? ""
        XCTAssertTrue(system.contains("Working memory"))
        XCTAssertTrue(system.contains("Clean Downloads"))
        XCTAssertGreaterThan(assembly.occupancy, 0)
        XCTAssertLessThanOrEqual(assembly.occupancy, 1)
        XCTAssertFalse(assembly.didExceedBudget)
    }

    func testSkillsCatalogStubsWhenBudgetIsTight() {
        let budget = PromptBudget(windowTokens: 60, reservedOutputTokens: 6, reservedToolTokens: 0)
        let catalog = """

        ## Available Skills
        - **alpha**: \(String(repeating: "desc ", count: 80))
        - **beta**: \(String(repeating: "more ", count: 80))
        """
        let current = AgentEvent(kind: .userInput, content: "go")
        let assembly = ContextBudget.assemble(
            PromptLayout(
                budget: budget,
                baseInstructions: "You are Sage.",
                workPlanAppendix: "\n## Confirmed work plan\nIntent: keep going\n",
                skillsCatalog: catalog,
                events: [current]
            )
        )
        let system = assembly.events.first { $0.kind == .systemInstruction }?.content ?? ""
        XCTAssertTrue(system.contains("You are Sage."))
        XCTAssertTrue(system.contains("Confirmed work plan") || system.contains("Intent: keep going"))
        XCTAssertFalse(system.contains("**alpha**"))
        XCTAssertTrue(assembly.events.contains { $0.id == current.id })
    }

    func testCapabilityReminderAndTodosStayInSystem() {
        let current = AgentEvent(kind: .userInput, content: "go")
        let assembly = ContextBudget.assemble(
            PromptLayout(
                budget: .default,
                baseInstructions: "You are Sage.",
                capabilityReminder: "\n## Runtime\nWork plan kind: act",
                todoAppendix: "\n## Todo list\nnot-started\t1\tRead file",
                events: [current]
            )
        )
        let system = assembly.events.first { $0.kind == .systemInstruction }?.content ?? ""
        XCTAssertTrue(system.contains("Work plan kind: act"))
        XCTAssertTrue(system.contains("Todo list"))
    }
}

final class PromptBudgetTests: XCTestCase {
    func testEmptyTextIsZeroTokens() {
        XCTAssertEqual(PromptBudget.estimatedTokenCount(in: ""), 0)
    }

    func testTokenEstimateRoundsUp() {
        XCTAssertEqual(PromptBudget.estimatedTokenCount(utf8ByteCount: 1), 1)
        XCTAssertEqual(PromptBudget.estimatedTokenCount(utf8ByteCount: 4), 1)
        XCTAssertEqual(PromptBudget.estimatedTokenCount(utf8ByteCount: 5), 2)
    }

    func testTokenEstimateDoesNotUndercountCJKAndEmoji() {
        XCTAssertEqual(PromptBudget.estimatedTokenCount(in: "你好世界"), 4)
        XCTAssertEqual(PromptBudget.estimatedTokenCount(in: "😀"), 2)
        XCTAssertEqual(PromptBudget.estimatedTokenCount(in: "abcd"), 1)
    }

    func testUsableSubtractsReserves() {
        let budget = PromptBudget(
            windowTokens: 1_000,
            reservedOutputTokens: 100,
            reservedToolTokens: 50
        )
        XCTAssertEqual(budget.usableTokens, 850)
        XCTAssertEqual(budget.maxToolResultTokens, 500)
    }
}
