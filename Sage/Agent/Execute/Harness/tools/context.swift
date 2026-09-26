//
//  context.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session / TurnContext / StepContext wait for Phase 5. Invocation carries
//  the call identity plus optional session callbacks handlers need.
//

import CodexAsyncUtils
import CodexCore
import CodexProtocol
import Foundation

enum ToolPayload: Equatable, Sendable {
    case function(arguments: String)
    case toolSearch(arguments: SearchToolCallParams)
    case custom(input: String)

    func logPayload() -> String {
        switch self {
        case .function(let arguments): return arguments
        case .toolSearch(let arguments): return arguments.query
        case .custom(let input): return input
        }
    }
}

enum ToolCallSource: Equatable, Sendable {
    case direct
    case directPlaintextMessage
    case codeMode(cellId: String, runtimeToolCallId: String)
}

protocol ToolOutput: Sendable {
    func logOutput() -> String
    func successForLogging() -> Bool
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON
    func postToolUseResponse(callId: String, payload: ToolPayload) -> HarnessJSON?
}

extension ToolOutput {
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        .string(logOutput())
    }

    func postToolUseResponse(callId: String, payload: ToolPayload) -> HarnessJSON? {
        nil
    }
}

func boxedToolOutput(_ output: some ToolOutput) -> any ToolOutput {
    output
}

struct ToolInvocation: Sendable {
    var callId: String
    var toolName: ToolName
    var source: ToolCallSource
    var payload: ToolPayload
    var cancellationToken: CancellationToken
    var turnId: String
    var threadId: ThreadId?
    var modeKind: ModeKind
    var tokensRemaining: Int64?
    var clock: @Sendable () -> Date
    var isRootThread: Bool
    var availableModes: [ModeKind]
    var onPlanUpdate: (@Sendable (UpdatePlanArgs) -> Void)?
    var onNewContextWindow: (@Sendable () -> Void)?
    var onAsyncUserMessage: (@Sendable (String) -> Void)?
    var onRequestPermissions: (@Sendable (RequestPermissionsArgs) async -> RequestPermissionsResponse?)?
    var onRequestUserInput: (@Sendable (RequestUserInputArgs) async -> RequestUserInputResponse?)?
    var onRequestUserInputAsync: (@Sendable ([AsyncUserInputQuestion]) -> Void)?
    var onViewImage: (@Sendable (String) async -> String?)?
    var onDynamicTool: (@Sendable (ToolName, HarnessJSON) async -> DynamicToolResponse?)?
    var onMcpCall: (@Sendable (String, String, HarnessJSON) async -> String?)?
    var onWaitForEnvironment: (@Sendable () async -> String?)?

    init(
        callId: String,
        toolName: ToolName,
        source: ToolCallSource = .direct,
        payload: ToolPayload,
        cancellationToken: CancellationToken = CancellationToken(),
        turnId: String = "",
        threadId: ThreadId? = nil,
        modeKind: ModeKind = .default,
        tokensRemaining: Int64? = nil,
        clock: @escaping @Sendable () -> Date = Date.init,
        isRootThread: Bool = true,
        availableModes: [ModeKind] = [.plan],
        onPlanUpdate: (@Sendable (UpdatePlanArgs) -> Void)? = nil,
        onNewContextWindow: (@Sendable () -> Void)? = nil,
        onAsyncUserMessage: (@Sendable (String) -> Void)? = nil,
        onRequestPermissions: (@Sendable (RequestPermissionsArgs) async -> RequestPermissionsResponse?)? = nil,
        onRequestUserInput: (@Sendable (RequestUserInputArgs) async -> RequestUserInputResponse?)? = nil,
        onRequestUserInputAsync: (@Sendable ([AsyncUserInputQuestion]) -> Void)? = nil,
        onViewImage: (@Sendable (String) async -> String?)? = nil,
        onDynamicTool: (@Sendable (ToolName, HarnessJSON) async -> DynamicToolResponse?)? = nil,
        onMcpCall: (@Sendable (String, String, HarnessJSON) async -> String?)? = nil,
        onWaitForEnvironment: (@Sendable () async -> String?)? = nil
    ) {
        self.callId = callId
        self.toolName = toolName
        self.source = source
        self.payload = payload
        self.cancellationToken = cancellationToken
        self.turnId = turnId
        self.threadId = threadId
        self.modeKind = modeKind
        self.tokensRemaining = tokensRemaining
        self.clock = clock
        self.isRootThread = isRootThread
        self.availableModes = availableModes
        self.onPlanUpdate = onPlanUpdate
        self.onNewContextWindow = onNewContextWindow
        self.onAsyncUserMessage = onAsyncUserMessage
        self.onRequestPermissions = onRequestPermissions
        self.onRequestUserInput = onRequestUserInput
        self.onRequestUserInputAsync = onRequestUserInputAsync
        self.onViewImage = onViewImage
        self.onDynamicTool = onDynamicTool
        self.onMcpCall = onMcpCall
        self.onWaitForEnvironment = onWaitForEnvironment
    }
}

struct FunctionToolOutput: ToolOutput, Sendable {
    var body: [FunctionCallOutputContentItem]
    var success: Bool?
    var postToolUse: HarnessJSON?

    static func fromText(_ text: String, success: Bool? = nil) -> FunctionToolOutput {
        FunctionToolOutput(
            body: [.inputText(text: text)],
            success: success
        )
    }

    static func fromContent(_ body: [FunctionCallOutputContentItem], success: Bool? = nil) -> FunctionToolOutput {
        FunctionToolOutput(body: body, success: success)
    }

    func logOutput() -> String {
        functionCallOutputContentItemsToText(body) ?? ""
    }

    func successForLogging() -> Bool {
        success ?? true
    }

    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        functionToolResponse(callId: callId, payload: payload, body: body, success: success)
    }

    func postToolUseResponse(callId: String, payload: ToolPayload) -> HarnessJSON? {
        postToolUse
    }
}

struct ApplyPatchToolOutput: ToolOutput, Sendable {
    var text: String

    static func fromText(_ text: String) -> ApplyPatchToolOutput {
        ApplyPatchToolOutput(text: text)
    }

    func logOutput() -> String { text }
    func successForLogging() -> Bool { true }

    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        functionToolResponse(
            callId: callId,
            payload: payload,
            body: [.inputText(text: text)],
            success: true
        )
    }

    func postToolUseResponse(callId: String, payload: ToolPayload) -> HarnessJSON? {
        .string(text)
    }

    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        .object([:])
    }
}

func functionToolResponse(
    callId: String,
    payload: ToolPayload,
    body: [FunctionCallOutputContentItem],
    success: Bool?
) -> ResponseInputItem {
    switch payload {
    case .custom:
        return .customToolCallOutput(
            callId: callId,
            name: nil,
            output: FunctionCallOutputPayload(body: .contentItems(body), success: success)
        )
    case .function, .toolSearch:
        return .functionCallOutput(
            callId: callId,
            output: FunctionCallOutputPayload(body: .contentItems(body), success: success)
        )
    }
}

struct ToolCallState: Sendable {
    var terminalOutcomeReached = false
    var deliveredAssistantMessage: String?
}

func parseToolArguments<T: Decodable>(_ arguments: String) throws -> T {
    let data = Data(arguments.utf8)
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw FunctionCallError.respondToModel("failed to parse function arguments: \(error)")
    }
}
