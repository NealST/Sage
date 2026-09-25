//
//  items.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/items.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `ExtensionItem` is a type placeholder until the extension-items crate is
//  ported. Hook-prompt XML uses a hand-rolled serializer (quick-xml upstream).
//  `PathBuf` map keys are ported as `String`.
//

import CodexUtils
import Foundation

// MARK: - TurnItem

/// serde `tag = "type"` (Rust variant names, not snake_case).
public enum TurnItem: Equatable, Sendable {
    case userMessage(UserMessageItem)
    case functionCallOutput(FunctionCallOutputItem)
    case hookPrompt(HookPromptItem)
    case agentMessage(AgentMessageItem)
    case plan(PlanItem)
    case reasoning(ReasoningItem)
    case commandExecution(CommandExecutionItem)
    case dynamicToolCall(DynamicToolCallItem)
    case collabAgentToolCall(CollabAgentToolCallItem)
    case subAgentActivity(SubAgentActivityItem)
    case webSearch(WebSearchItem)
    case imageView(ImageViewItem)
    case `extension`(ExtensionItem)
    case imageGeneration(ImageGenerationItem)
    case enteredReviewMode(EnteredReviewModeItem)
    case exitedReviewMode(ExitedReviewModeItem)
    case fileChange(FileChangeItem)
    case mcpToolCall(McpToolCallItem)
    case contextCompaction(ContextCompactionItem)

    public var id: String {
        switch self {
        case .userMessage(let item): return item.id
        case .functionCallOutput(let item): return item.id
        case .hookPrompt(let item): return item.id
        case .agentMessage(let item): return item.id
        case .plan(let item): return item.id
        case .reasoning(let item): return item.id
        case .commandExecution(let item): return item.id
        case .dynamicToolCall(let item): return item.id
        case .collabAgentToolCall(let item): return item.id
        case .subAgentActivity(let item): return item.id
        case .webSearch(let item): return item.id
        case .imageView(let item): return item.id
        case .extension(let item): return item.id
        case .imageGeneration(let item): return item.id
        case .enteredReviewMode(let item): return item.id
        case .exitedReviewMode(let item): return item.id
        case .fileChange(let item): return item.id
        case .mcpToolCall(let item): return item.id
        case .contextCompaction(let item): return item.id
        }
    }
}

extension TurnItem: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "UserMessage": self = .userMessage(try UserMessageItem(from: decoder))
        case "FunctionCallOutput": self = .functionCallOutput(try FunctionCallOutputItem(from: decoder))
        case "HookPrompt": self = .hookPrompt(try HookPromptItem(from: decoder))
        case "AgentMessage": self = .agentMessage(try AgentMessageItem(from: decoder))
        case "Plan": self = .plan(try PlanItem(from: decoder))
        case "Reasoning": self = .reasoning(try ReasoningItem(from: decoder))
        case "CommandExecution": self = .commandExecution(try CommandExecutionItem(from: decoder))
        case "DynamicToolCall": self = .dynamicToolCall(try DynamicToolCallItem(from: decoder))
        case "CollabAgentToolCall": self = .collabAgentToolCall(try CollabAgentToolCallItem(from: decoder))
        case "SubAgentActivity": self = .subAgentActivity(try SubAgentActivityItem(from: decoder))
        case "WebSearch": self = .webSearch(try WebSearchItem(from: decoder))
        case "ImageView": self = .imageView(try ImageViewItem(from: decoder))
        case "Extension": self = .extension(try ExtensionItem(from: decoder))
        case "ImageGeneration": self = .imageGeneration(try ImageGenerationItem(from: decoder))
        case "EnteredReviewMode": self = .enteredReviewMode(try EnteredReviewModeItem(from: decoder))
        case "ExitedReviewMode": self = .exitedReviewMode(try ExitedReviewModeItem(from: decoder))
        case "FileChange": self = .fileChange(try FileChangeItem(from: decoder))
        case "McpToolCall": self = .mcpToolCall(try McpToolCallItem(from: decoder))
        case "ContextCompaction": self = .contextCompaction(try ContextCompactionItem(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container, debugDescription: "Unknown TurnItem: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .userMessage(let item):
            try container.encode("UserMessage", forKey: .type_); try item.encode(to: encoder)
        case .functionCallOutput(let item):
            try container.encode("FunctionCallOutput", forKey: .type_); try item.encode(to: encoder)
        case .hookPrompt(let item):
            try container.encode("HookPrompt", forKey: .type_); try item.encode(to: encoder)
        case .agentMessage(let item):
            try container.encode("AgentMessage", forKey: .type_); try item.encode(to: encoder)
        case .plan(let item):
            try container.encode("Plan", forKey: .type_); try item.encode(to: encoder)
        case .reasoning(let item):
            try container.encode("Reasoning", forKey: .type_); try item.encode(to: encoder)
        case .commandExecution(let item):
            try container.encode("CommandExecution", forKey: .type_); try item.encode(to: encoder)
        case .dynamicToolCall(let item):
            try container.encode("DynamicToolCall", forKey: .type_); try item.encode(to: encoder)
        case .collabAgentToolCall(let item):
            try container.encode("CollabAgentToolCall", forKey: .type_); try item.encode(to: encoder)
        case .subAgentActivity(let item):
            try container.encode("SubAgentActivity", forKey: .type_); try item.encode(to: encoder)
        case .webSearch(let item):
            try container.encode("WebSearch", forKey: .type_); try item.encode(to: encoder)
        case .imageView(let item):
            try container.encode("ImageView", forKey: .type_); try item.encode(to: encoder)
        case .extension(let item):
            try container.encode("Extension", forKey: .type_); try item.encode(to: encoder)
        case .imageGeneration(let item):
            try container.encode("ImageGeneration", forKey: .type_); try item.encode(to: encoder)
        case .enteredReviewMode(let item):
            try container.encode("EnteredReviewMode", forKey: .type_); try item.encode(to: encoder)
        case .exitedReviewMode(let item):
            try container.encode("ExitedReviewMode", forKey: .type_); try item.encode(to: encoder)
        case .fileChange(let item):
            try container.encode("FileChange", forKey: .type_); try item.encode(to: encoder)
        case .mcpToolCall(let item):
            try container.encode("McpToolCall", forKey: .type_); try item.encode(to: encoder)
        case .contextCompaction(let item):
            try container.encode("ContextCompaction", forKey: .type_); try item.encode(to: encoder)
        }
    }
}

/// Placeholder until `codex_extension_items::ExtensionItem` is ported.
/// Flattened beside TurnItem's `type` tag; `kind` identifies the extension.
public struct ExtensionItem: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    public var extra: [String: JSONValue]

    public init(kind: String, id: String, extra: [String: JSONValue] = [:]) {
        self.kind = kind; self.id = id; self.extra = extra
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: JSONCodingKey.self)
        kind = try container.decode(String.self, forKey: JSONCodingKey("kind"))
        id = try container.decode(String.self, forKey: JSONCodingKey("id"))
        var extra: [String: JSONValue] = [:]
        for key in container.allKeys where key.stringValue != "type" && key.stringValue != "kind"
            && key.stringValue != "id"
        {
            extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.extra = extra
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONCodingKey.self)
        try container.encode(kind, forKey: JSONCodingKey("kind"))
        try container.encode(id, forKey: JSONCodingKey("id"))
        for key in extra.keys.sorted() {
            try container.encode(extra[key], forKey: JSONCodingKey(key))
        }
    }
}

public struct UserMessageItem: Codable, Equatable, Sendable {
    public var id: String
    public var clientId: String?
    public var content: [UserInput]

    enum CodingKeys: String, CodingKey {
        case id, content
        case clientId = "client_id"
    }

    public init(id: String, clientId: String? = nil, content: [UserInput]) {
        self.id = id; self.clientId = clientId; self.content = content
    }

    public init(_ content: [UserInput]) {
        self.init(id: newItemId(), content: content)
    }

    public func message() -> String {
        content.map { item in
            if case .text(let text, _) = item { return text }
            return ""
        }.joined()
    }

    public func textElements() -> [TextElement] {
        var out: [TextElement] = []
        var offset = 0
        for input in content {
            if case .text(let text, let elements) = input {
                for elem in elements {
                    out.append(
                        TextElement(
                            byteRange: ByteRange(
                                start: offset + elem.byteRange.start,
                                end: offset + elem.byteRange.end),
                            placeholder: elem.placeholder(in: text)))
                }
                offset += text.utf8.count
            }
        }
        return out
    }

    public func imageUrls() -> [String] {
        content.compactMap { item in
            if case .image(let image, _) = item, case .inline(let url) = image { return url }
            return nil
        }
    }

    public func imageDetails() -> [ImageDetail?] {
        trimTrailingDefaultImageDetails(
            content.compactMap { item -> ImageDetail?? in
                if case .image(let image, let detail) = item, case .inline = image {
                    return detail
                }
                return nil
            }.map { $0 })
    }

    public func localImagePaths() -> [String] {
        content.compactMap { item in
            if case .localImage(let path, _) = item { return path }
            return nil
        }
    }

    public func localImageDetails() -> [ImageDetail?] {
        trimTrailingDefaultImageDetails(
            content.compactMap { item -> ImageDetail?? in
                if case .localImage(_, let detail) = item { return detail }
                return nil
            }.map { $0 })
    }

    public func audioUrls() -> [String] {
        content.compactMap { item in
            if case .audio(let url) = item { return url }
            return nil
        }
    }

    public func localAudioPaths() -> [String] {
        content.compactMap { item in
            if case .localAudio(let path) = item { return path }
            return nil
        }
    }
}

public struct FunctionCallOutputItem: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var namespace: String?
    public var output: FunctionCallOutputBody

    public init(id: String, name: String, namespace: String? = nil, output: FunctionCallOutputBody) {
        self.id = id; self.name = name; self.namespace = namespace; self.output = output
    }
}

public struct HookPromptItem: Codable, Equatable, Sendable {
    public var id: String
    public var fragments: [HookPromptFragment]

    public init(id: String, fragments: [HookPromptFragment]) {
        self.id = id; self.fragments = fragments
    }

    public static func fromFragments(id: String?, fragments: [HookPromptFragment]) -> HookPromptItem {
        HookPromptItem(id: id ?? newItemId(), fragments: fragments)
    }
}

public struct HookPromptFragment: Codable, Equatable, Sendable {
    public var text: String
    public var hookRunId: String

    public init(text: String, hookRunId: String) {
        self.text = text; self.hookRunId = hookRunId
    }

    public static func fromSingleHook(text: String, hookRunId: String) -> HookPromptFragment {
        HookPromptFragment(text: text, hookRunId: hookRunId)
    }
}

public enum AgentMessageContent: Codable, Equatable, Sendable {
    case text(text: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case text }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "Text":
            self = .text(text: try keys.decode(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown AgentMessageContent: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        try container.encode("Text", forKey: .type_)
        switch self {
        case .text(let text): try keys.encode(text, forKey: .text)
        }
    }
}

public enum AgentMessageDelivery: String, Codable, Equatable, Sendable {
    case async
}

public struct AsyncUserInputQuestion: Codable, Equatable, Sendable {
    public var title: String
    public var options: [String]?

    public init(title: String, options: [String]? = nil) {
        self.title = title; self.options = options
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "AsyncUserInputQuestion")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        options = try container.decodeIfPresent([String].self, forKey: .options)
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case title, options }
}

public struct AgentMessageItem: Codable, Equatable, Sendable {
    public var id: String
    public var content: [AgentMessageContent]
    public var phase: MessagePhase?
    public var memoryCitation: MemoryCitation?
    public var delivery: AgentMessageDelivery?
    public var questions: [AsyncUserInputQuestion]?

    enum CodingKeys: String, CodingKey {
        case id, content, phase, delivery, questions
        case memoryCitation = "memory_citation"
    }

    public init(
        id: String, content: [AgentMessageContent], phase: MessagePhase? = nil,
        memoryCitation: MemoryCitation? = nil, delivery: AgentMessageDelivery? = nil,
        questions: [AsyncUserInputQuestion]? = nil
    ) {
        self.id = id; self.content = content; self.phase = phase
        self.memoryCitation = memoryCitation; self.delivery = delivery
        self.questions = questions
    }
}

public struct EnteredReviewModeItem: Codable, Equatable, Sendable {
    public var id: String
    public var target: ReviewTarget
    public var userFacingHint: String

    enum CodingKeys: String, CodingKey {
        case id, target
        case userFacingHint = "user_facing_hint"
    }

    public init(id: String, target: ReviewTarget, userFacingHint: String) {
        self.id = id; self.target = target; self.userFacingHint = userFacingHint
    }
}

public struct ExitedReviewModeItem: Codable, Equatable, Sendable {
    public var id: String
    public var reviewOutput: ReviewOutputEvent?

    enum CodingKeys: String, CodingKey {
        case id
        case reviewOutput = "review_output"
    }

    public init(id: String, reviewOutput: ReviewOutputEvent?) {
        self.id = id; self.reviewOutput = reviewOutput
    }
}

public struct PlanItem: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

public struct ReasoningItem: Codable, Equatable, Sendable {
    public var id: String
    public var summaryText: [String]
    public var rawContent: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case summaryText = "summary_text"
        case rawContent = "raw_content"
    }

    public init(id: String, summaryText: [String], rawContent: [String] = []) {
        self.id = id; self.summaryText = summaryText; self.rawContent = rawContent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        summaryText = try container.decode([String].self, forKey: .summaryText)
        rawContent = try container.decodeIfPresent([String].self, forKey: .rawContent) ?? []
    }
}

public enum CommandExecutionStatus: String, Codable, Equatable, Sendable {
    case inProgress = "in_progress"
    case completed
    case failed
    case declined

    public init(_ value: ExecCommandStatus) {
        switch value {
        case .completed: self = .completed
        case .failed: self = .failed
        case .declined: self = .declined
        }
    }
}

/// Returns whether a path is safe to serialize as a trusted plugin-relative path.
public func isSafePluginRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
    return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
        !component.isEmpty
            && component != "."
            && component != ".."
            && !(component.utf8.count >= 2
                && component.utf8.first!.isASCIIAlphabetic
                && component.utf8.dropFirst().first == UInt8(ascii: ":"))
    }
}

/// Immutable model labels carried within command lifecycle events for analytics.
public struct ModelInvocationContext: Equatable, Sendable {
    public var modelSlug: String
    public var reasoningEffort: String?

    public init(modelSlug: String, reasoningEffort: String? = nil) {
        self.modelSlug = modelSlug
        self.reasoningEffort = reasoningEffort
    }
}

public struct CommandExecutionItem: Equatable, Sendable {
    public var sandboxType: SandboxType?
    public var modelContext: ModelInvocationContext?
    public var id: String
    public var pluginId: String?
    public var scriptPath: String?
    public var processId: String?
    public var command: [String]
    public var cwd: PathUri
    public var parsedCmd: [ParsedCommand]
    public var source: ExecCommandSource
    public var interactionInput: String?
    public var status: CommandExecutionStatus
    public var stdout: String?
    public var stderr: String?
    public var aggregatedOutput: String?
    public var exitCode: Int32?
    public var duration: Duration?
    public var formattedOutput: String?

    public init(
        sandboxType: SandboxType? = nil,
        modelContext: ModelInvocationContext? = nil,
        id: String,
        pluginId: String? = nil,
        scriptPath: String? = nil,
        processId: String? = nil,
        command: [String],
        cwd: PathUri,
        parsedCmd: [ParsedCommand],
        source: ExecCommandSource,
        interactionInput: String? = nil,
        status: CommandExecutionStatus,
        stdout: String? = nil,
        stderr: String? = nil,
        aggregatedOutput: String? = nil,
        exitCode: Int32? = nil,
        duration: Duration? = nil,
        formattedOutput: String? = nil
    ) {
        self.sandboxType = sandboxType; self.modelContext = modelContext
        self.id = id; self.pluginId = pluginId; self.scriptPath = scriptPath
        self.processId = processId; self.command = command; self.cwd = cwd
        self.parsedCmd = parsedCmd; self.source = source
        self.interactionInput = interactionInput; self.status = status
        self.stdout = stdout; self.stderr = stderr
        self.aggregatedOutput = aggregatedOutput; self.exitCode = exitCode
        self.duration = duration; self.formattedOutput = formattedOutput
    }
}

extension CommandExecutionItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, command, cwd, source, status, stdout, stderr, duration
        case pluginId = "plugin_id"
        case scriptPath = "script_path"
        case processId = "process_id"
        case parsedCmd = "parsed_cmd"
        case interactionInput = "interaction_input"
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
        case formattedOutput = "formatted_output"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sandboxType = nil
        modelContext = nil
        id = try container.decode(String.self, forKey: .id)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        scriptPath = try container.decodeIfPresent(String.self, forKey: .scriptPath)
        processId = try container.decodeIfPresent(String.self, forKey: .processId)
        command = try container.decode([String].self, forKey: .command)
        cwd = try container.decode(PathUri.self, forKey: .cwd)
        parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
        source = try container.decode(ExecCommandSource.self, forKey: .source)
        interactionInput = try container.decodeIfPresent(String.self, forKey: .interactionInput)
        status = try container.decode(CommandExecutionStatus.self, forKey: .status)
        stdout = try container.decodeIfPresent(String.self, forKey: .stdout)
        stderr = try container.decodeIfPresent(String.self, forKey: .stderr)
        aggregatedOutput = try container.decodeIfPresent(String.self, forKey: .aggregatedOutput)
        exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        duration = try container.decodeIfPresent(SerdeDuration.self, forKey: .duration)?.duration
        formattedOutput = try container.decodeIfPresent(String.self, forKey: .formattedOutput)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(pluginId, forKey: .pluginId)
        try container.encodeIfPresent(scriptPath, forKey: .scriptPath)
        try container.encodeIfPresent(processId, forKey: .processId)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(parsedCmd, forKey: .parsedCmd)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(interactionInput, forKey: .interactionInput)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(stdout, forKey: .stdout)
        try container.encodeIfPresent(stderr, forKey: .stderr)
        try container.encodeIfPresent(aggregatedOutput, forKey: .aggregatedOutput)
        try container.encodeIfPresent(exitCode, forKey: .exitCode)
        if let duration {
            try container.encode(SerdeDuration(duration), forKey: .duration)
        }
        try container.encodeIfPresent(formattedOutput, forKey: .formattedOutput)
    }
}

public enum DynamicToolCallStatus: String, Codable, Equatable, Sendable {
    case inProgress = "in_progress"
    case completed
    case failed
}

public struct DynamicToolCallItem: Codable, Equatable, Sendable {
    public var id: String
    public var namespace: String?
    public var tool: String
    public var arguments: JSONValue
    public var status: DynamicToolCallStatus
    public var contentItems: [DynamicToolCallOutputContentItem]?
    public var success: Bool?
    public var error: String?
    public var duration: Duration?

    enum CodingKeys: String, CodingKey {
        case id, namespace, tool, arguments, status, success, error, duration
        case contentItems = "content_items"
    }

    public init(
        id: String, namespace: String? = nil, tool: String, arguments: JSONValue,
        status: DynamicToolCallStatus, contentItems: [DynamicToolCallOutputContentItem]? = nil,
        success: Bool? = nil, error: String? = nil, duration: Duration? = nil
    ) {
        self.id = id; self.namespace = namespace; self.tool = tool
        self.arguments = arguments; self.status = status
        self.contentItems = contentItems; self.success = success
        self.error = error; self.duration = duration
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
        status = try container.decode(DynamicToolCallStatus.self, forKey: .status)
        contentItems = try container.decodeIfPresent(
            [DynamicToolCallOutputContentItem].self, forKey: .contentItems)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        duration = try container.decodeIfPresent(SerdeDuration.self, forKey: .duration)?.duration
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(namespace, forKey: .namespace)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(contentItems, forKey: .contentItems)
        try container.encodeIfPresent(success, forKey: .success)
        try container.encodeIfPresent(error, forKey: .error)
        if let duration { try container.encode(SerdeDuration(duration), forKey: .duration) }
    }
}

public enum CollabAgentTool: String, Codable, Equatable, Sendable {
    case spawnAgent = "spawn_agent"
    case sendInput = "send_input"
    case resumeAgent = "resume_agent"
    case wait
    case closeAgent = "close_agent"
    case sendMessage = "send_message"
    case followupTask = "followup_task"
    case interruptAgent = "interrupt_agent"
    case listAgents = "list_agents"
}

public enum CollabAgentToolCallStatus: String, Codable, Equatable, Sendable {
    case inProgress = "in_progress"
    case completed
    case failed
    case interrupted
}

public struct CollabAgentToolCallItem: Equatable, Sendable {
    public var id: String
    public var tool: CollabAgentTool
    public var status: CollabAgentToolCallStatus
    public var senderThreadId: ThreadId
    public var receiverThreadIds: [ThreadId]
    public var receiverAgents: [CollabAgentRef]
    public var prompt: String?
    public var model: String?
    public var reasoningEffort: ReasoningEffort?
    public var agentsStates: [ThreadId: AgentStatus]

    public init(
        id: String, tool: CollabAgentTool, status: CollabAgentToolCallStatus,
        senderThreadId: ThreadId, receiverThreadIds: [ThreadId] = [],
        receiverAgents: [CollabAgentRef] = [], prompt: String? = nil, model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil, agentsStates: [ThreadId: AgentStatus] = [:]
    ) {
        self.id = id; self.tool = tool; self.status = status
        self.senderThreadId = senderThreadId; self.receiverThreadIds = receiverThreadIds
        self.receiverAgents = receiverAgents; self.prompt = prompt; self.model = model
        self.reasoningEffort = reasoningEffort; self.agentsStates = agentsStates
    }
}

extension CollabAgentToolCallItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, tool, status, prompt, model
        case senderThreadId = "sender_thread_id"
        case receiverThreadIds = "receiver_thread_ids"
        case receiverAgents = "receiver_agents"
        case reasoningEffort = "reasoning_effort"
        case agentsStates = "agents_states"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tool = try container.decode(CollabAgentTool.self, forKey: .tool)
        status = try container.decode(CollabAgentToolCallStatus.self, forKey: .status)
        senderThreadId = try container.decode(ThreadId.self, forKey: .senderThreadId)
        receiverThreadIds = try container.decodeIfPresent([ThreadId].self, forKey: .receiverThreadIds) ?? []
        receiverAgents = try container.decodeIfPresent([CollabAgentRef].self, forKey: .receiverAgents) ?? []
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        let rawStates = try container.decodeIfPresent([String: AgentStatus].self, forKey: .agentsStates) ?? [:]
        var states: [ThreadId: AgentStatus] = [:]
        for (key, value) in rawStates {
            if let threadId = try? ThreadId.fromString(key) { states[threadId] = value }
        }
        agentsStates = states
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tool, forKey: .tool)
        try container.encode(status, forKey: .status)
        try container.encode(senderThreadId, forKey: .senderThreadId)
        try container.encode(receiverThreadIds, forKey: .receiverThreadIds)
        try container.encode(receiverAgents, forKey: .receiverAgents)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        var raw: [String: AgentStatus] = [:]
        for (key, value) in agentsStates { raw[key.description] = value }
        try container.encode(raw, forKey: .agentsStates)
    }
}

public struct SubAgentActivityItem: Codable, Equatable, Sendable {
    public var id: String
    public var kind: SubAgentActivityKind
    public var agentThreadId: ThreadId
    public var agentPath: AgentPath

    enum CodingKeys: String, CodingKey {
        case id, kind
        case agentThreadId = "agent_thread_id"
        case agentPath = "agent_path"
    }

    public init(id: String, kind: SubAgentActivityKind, agentThreadId: ThreadId, agentPath: AgentPath) {
        self.id = id; self.kind = kind; self.agentThreadId = agentThreadId; self.agentPath = agentPath
    }
}

public struct WebSearchItem: Codable, Equatable, Sendable {
    public var id: String
    public var query: String
    public var action: WebSearchAction
    public var results: [JSONValue]?

    public init(id: String, query: String, action: WebSearchAction, results: [JSONValue]? = nil) {
        self.id = id; self.query = query; self.action = action; self.results = results
    }
}

public struct ImageViewItem: Codable, Equatable, Sendable {
    public var id: String
    public var path: PathUri
    public init(id: String, path: PathUri) { self.id = id; self.path = path }
}

public struct ImageGenerationItem: Codable, Equatable, Sendable {
    public var id: String
    public var status: String
    public var revisedPrompt: String?
    public var result: String
    public var savedPath: AbsolutePathBuf?

    enum CodingKeys: String, CodingKey {
        case id, status, result
        case revisedPrompt = "revised_prompt"
        case savedPath = "saved_path"
    }

    public init(
        id: String, status: String, revisedPrompt: String? = nil, result: String,
        savedPath: AbsolutePathBuf? = nil
    ) {
        self.id = id; self.status = status; self.revisedPrompt = revisedPrompt
        self.result = result; self.savedPath = savedPath
    }
}

public struct FileChangeItem: Codable, Equatable, Sendable {
    public var id: String
    public var changes: [String: FileChange]
    public var status: PatchApplyStatus?
    public var autoApproved: Bool?
    public var stdout: String?
    public var stderr: String?

    enum CodingKeys: String, CodingKey {
        case id, changes, status, stdout, stderr
        case autoApproved = "auto_approved"
    }

    public init(
        id: String, changes: [String: FileChange], status: PatchApplyStatus? = nil,
        autoApproved: Bool? = nil, stdout: String? = nil, stderr: String? = nil
    ) {
        self.id = id; self.changes = changes; self.status = status
        self.autoApproved = autoApproved; self.stdout = stdout; self.stderr = stderr
    }
}

public struct McpAppUi: Codable, Equatable, Sendable {
    public var resourceUri: String
    public var preferredModelDisplayMode: McpAppDisplayMode

    public init(resourceUri: String, preferredModelDisplayMode: McpAppDisplayMode) {
        self.resourceUri = resourceUri
        self.preferredModelDisplayMode = preferredModelDisplayMode
    }
}

public enum McpAppDisplayMode: String, Codable, Equatable, Sendable {
    case inline
    case fullscreen
}

public struct McpToolCallItem: Codable, Equatable, Sendable {
    public var id: String
    public var server: String
    public var tool: String
    public var arguments: JSONValue
    public var connectorId: String?
    public var mcpAppResourceUri: String?
    public var mcpAppUi: McpAppUi?
    public var linkId: String?
    public var appName: String?
    public var actionName: String?
    public var pluginId: String?
    public var readOnlyHint: Bool?
    public var status: McpToolCallStatus
    public var result: CallToolResult?
    public var error: McpToolCallError?
    public var duration: Duration?

    public init(
        id: String, server: String, tool: String, arguments: JSONValue,
        connectorId: String? = nil, mcpAppResourceUri: String? = nil,
        mcpAppUi: McpAppUi? = nil, linkId: String? = nil, appName: String? = nil,
        actionName: String? = nil, pluginId: String? = nil, readOnlyHint: Bool? = nil,
        status: McpToolCallStatus, result: CallToolResult? = nil,
        error: McpToolCallError? = nil, duration: Duration? = nil
    ) {
        self.id = id; self.server = server; self.tool = tool; self.arguments = arguments
        self.connectorId = connectorId; self.mcpAppResourceUri = mcpAppResourceUri
        self.mcpAppUi = mcpAppUi; self.linkId = linkId; self.appName = appName
        self.actionName = actionName; self.pluginId = pluginId; self.readOnlyHint = readOnlyHint
        self.status = status; self.result = result; self.error = error; self.duration = duration
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        server = try container.decode(String.self, forKey: .server)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
        connectorId = try container.decodeIfPresent(String.self, forKey: .connectorId)
        mcpAppResourceUri = try container.decodeIfPresent(String.self, forKey: .mcpAppResourceUri)
        mcpAppUi = try container.decodeIfPresent(McpAppUi.self, forKey: .mcpAppUi)
        linkId = try container.decodeIfPresent(String.self, forKey: .linkId)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        actionName = try container.decodeIfPresent(String.self, forKey: .actionName)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        readOnlyHint = try container.decodeIfPresent(Bool.self, forKey: .readOnlyHint)
        status = try container.decode(McpToolCallStatus.self, forKey: .status)
        result = try container.decodeIfPresent(CallToolResult.self, forKey: .result)
        error = try container.decodeIfPresent(McpToolCallError.self, forKey: .error)
        duration = try container.decodeIfPresent(SerdeDuration.self, forKey: .duration)?.duration
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(server, forKey: .server)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
        try container.encodeIfPresent(connectorId, forKey: .connectorId)
        try container.encodeIfPresent(mcpAppResourceUri, forKey: .mcpAppResourceUri)
        try container.encodeIfPresent(mcpAppUi, forKey: .mcpAppUi)
        try container.encodeIfPresent(linkId, forKey: .linkId)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encodeIfPresent(actionName, forKey: .actionName)
        try container.encodeIfPresent(pluginId, forKey: .pluginId)
        try container.encodeIfPresent(readOnlyHint, forKey: .readOnlyHint)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
        if let duration { try container.encode(SerdeDuration(duration), forKey: .duration) }
    }

    enum CodingKeys: String, CodingKey {
        case id, server, tool, arguments, status, result, error, duration
        case connectorId
        case mcpAppResourceUri
        case mcpAppUi
        case linkId
        case appName
        case actionName
        case pluginId
        case readOnlyHint
    }
}

public enum McpToolCallStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case failed
}

public struct McpToolCallError: Codable, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

public struct ContextCompactionItem: Codable, Equatable, Sendable {
    public var id: String
    public init(id: String) { self.id = id }
    public init() { self.id = newItemId() }
}

func newItemId() -> String {
    UUIDv7.now().uuidString.lowercased()
}

func trimTrailingDefaultImageDetails(_ details: [ImageDetail?]) -> [ImageDetail?] {
    var details = details
    while let last = details.last, last == nil { details.removeLast() }
    return details
}

public func buildHookPromptMessage(_ fragments: [HookPromptFragment]) -> ResponseItem? {
    let content: [ContentItem] = fragments.compactMap { fragment in
        guard !fragment.hookRunId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let text = serializeHookPromptFragment(fragment.text, hookRunId: fragment.hookRunId)
        else { return nil }
        return .inputText(text: text)
    }
    if content.isEmpty { return nil }
    return .message(
        id: ResponseItemId(new: "msg"),
        role: "user",
        content: content,
        phase: nil,
        internalChatMessageMetadataPassthrough: nil)
}

public func parseHookPromptMessage(id: String?, content: [ContentItem]) -> HookPromptItem? {
    var fragments: [HookPromptFragment] = []
    for contentItem in content {
        guard case .inputText(let text) = contentItem,
              let fragment = parseHookPromptFragment(text)
        else { return nil }
        fragments.append(fragment)
    }
    if fragments.isEmpty { return nil }
    return HookPromptItem.fromFragments(id: id, fragments: fragments)
}

public func parseHookPromptFragment(_ text: String) -> HookPromptFragment? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = parseHookPromptXml(trimmed),
          !parsed.hookRunId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return parsed
}

func serializeHookPromptFragment(_ text: String, hookRunId: String) -> String? {
    if hookRunId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    let escapedId = xmlEscapeAttribute(hookRunId)
    let escapedText = xmlEscapeText(text)
    return "<hook_prompt hook_run_id=\"\(escapedId)\">\(escapedText)</hook_prompt>"
}

private func parseHookPromptXml(_ text: String) -> HookPromptFragment? {
    let prefix = "<hook_prompt"
    let suffix = "</hook_prompt>"
    guard text.hasPrefix(prefix), text.hasSuffix(suffix) else { return nil }
    guard let gt = text.firstIndex(of: ">") else { return nil }
    let attrs = String(text[text.index(text.startIndex, offsetBy: prefix.count)..<gt])
    guard let runId = xmlAttribute(attrs, name: "hook_run_id") else { return nil }
    let innerStart = text.index(after: gt)
    let innerEnd = text.index(text.endIndex, offsetBy: -suffix.count)
    let inner = String(text[innerStart..<innerEnd])
    return HookPromptFragment(text: xmlUnescape(inner), hookRunId: xmlUnescape(runId))
}

private func xmlAttribute(_ attrs: String, name: String) -> String? {
    let needle = "\(name)=\""
    guard let range = attrs.range(of: needle) else { return nil }
    let rest = attrs[range.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end])
}

private func xmlEscapeAttribute(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
}

private func xmlEscapeText(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
}

private func xmlUnescape(_ value: String) -> String {
    value.replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&amp;", with: "&")
}

private extension UInt8 {
    var isASCIIAlphabetic: Bool {
        (self >= 65 && self <= 90) || (self >= 97 && self <= 122)
    }
}
