//
//  multi_agents_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_spec.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Tool names, required fields, and descriptions are faithful.
//  `with_encrypted()` is omitted (JsonSchema has no encrypted flag).
//  Output schemas use JSONValue objects instead of serde_json macros.
//

import CodexCore
import CodexProtocol

let MULTI_AGENT_V1_NAMESPACE = "multi_agent_v1"
let MULTI_AGENT_V1_NAMESPACE_DESCRIPTION = "Tools for spawning and managing sub-agents."
let SPAWN_AGENT_INHERITED_MODEL_GUIDANCE =
    "Spawned agents inherit your current model by default. Omit `model` to use that preferred default; set `model` only when an explicit override is needed."
let SPAWN_AGENT_TYPE_OVERRIDE_DESCRIPTION_V1 =
    "Agent type override for the new agent. Omit to inherit the parent agent type with a full-history fork; otherwise, `default` is used."
let SPAWN_AGENT_MODEL_OVERRIDE_DESCRIPTION =
    "Model override for the new agent. Omit unless an explicit override is needed."
let MAX_REASONING_EFFORT_CHARS_IN_SPAWN_AGENT_DESCRIPTION = 64

struct SpawnAgentToolOptions: Equatable, Sendable {
    var availableModels: [ModelPreset]
    var agentTypeDescription: String
    var exposeAgentType: Bool
    var hideAgentTypeModelReasoning: Bool
    var exposeSpawnAgentModelOverrides: Bool
    var multiAgentVersion: MultiAgentVersion
    var usageHintText: String?

    init(
        availableModels: [ModelPreset] = [],
        agentTypeDescription: String = "",
        exposeAgentType: Bool = true,
        hideAgentTypeModelReasoning: Bool = false,
        exposeSpawnAgentModelOverrides: Bool = false,
        multiAgentVersion: MultiAgentVersion = .disabled,
        usageHintText: String? = nil
    ) {
        self.availableModels = availableModels
        self.agentTypeDescription = agentTypeDescription
        self.exposeAgentType = exposeAgentType
        self.hideAgentTypeModelReasoning = hideAgentTypeModelReasoning
        self.exposeSpawnAgentModelOverrides = exposeSpawnAgentModelOverrides
        self.multiAgentVersion = multiAgentVersion
        self.usageHintText = usageHintText
    }
}

struct WaitAgentTimeoutOptions: Equatable, Sendable {
    var defaultTimeoutMs: Int64
    var minTimeoutMs: Int64
    var maxTimeoutMs: Int64

    init(
        defaultTimeoutMs: Int64 = DEFAULT_WAIT_TIMEOUT_MS,
        minTimeoutMs: Int64 = MIN_WAIT_TIMEOUT_MS,
        maxTimeoutMs: Int64 = MAX_WAIT_TIMEOUT_MS
    ) {
        self.defaultTimeoutMs = defaultTimeoutMs
        self.minTimeoutMs = minTimeoutMs
        self.maxTimeoutMs = maxTimeoutMs
    }
}

func createSpawnAgentToolV1(_ options: SpawnAgentToolOptions) -> ToolSpec {
    let availableModelsDescription = options.hideAgentTypeModelReasoning
        ? nil
        : spawnAgentModelsDescription(options.availableModels, options.multiAgentVersion)
    let inheritedModelGuidance = options.hideAgentTypeModelReasoning
        ? nil
        : SPAWN_AGENT_INHERITED_MODEL_GUIDANCE
    var properties = spawnAgentCommonPropertiesV1(options.agentTypeDescription)
    if !options.exposeAgentType {
        properties.removeValue(forKey: "agent_type")
    }
    if options.hideAgentTypeModelReasoning {
        hideSpawnAgentMetadataOptions(&properties)
    }
    return .namespace(
        ResponsesApiNamespace(
            name: MULTI_AGENT_V1_NAMESPACE,
            description: MULTI_AGENT_V1_NAMESPACE_DESCRIPTION,
            tools: [
                ResponsesApiNamespaceTool(
                    function: ResponsesApiTool(
                        name: "spawn_agent",
                        description: spawnAgentToolDescription(
                            availableModelsDescription: availableModelsDescription,
                            inheritedModelGuidance: inheritedModelGuidance,
                            returnValueDescription:
                                "Returns the spawned agent id plus the user-facing nickname when available.",
                            usageHintText: options.usageHintText
                        ),
                        strict: false,
                        parameters: .object(properties, additionalProperties: false),
                        outputSchema: spawnAgentOutputSchemaV1()
                    )
                )
            ]
        )
    )
}

func createSpawnAgentToolV2(
    _ options: SpawnAgentToolOptions,
    descriptionOverride: String? = nil
) -> ToolSpec {
    let availableModelsDescription = options.exposeSpawnAgentModelOverrides
        ? spawnAgentModelsDescription(options.availableModels, options.multiAgentVersion)
        : nil
    let inheritedModelGuidance =
        options.exposeSpawnAgentModelOverrides && !options.hideAgentTypeModelReasoning
        ? SPAWN_AGENT_INHERITED_MODEL_GUIDANCE
        : nil
    var properties = spawnAgentCommonPropertiesV2(options.agentTypeDescription)
    if !options.exposeAgentType {
        properties.removeValue(forKey: "agent_type")
    }
    if !options.exposeSpawnAgentModelOverrides {
        properties.removeValue(forKey: "model")
        properties.removeValue(forKey: "reasoning_effort")
    }
    properties["task_name"] = .string(
        "Task name for the new agent. Use lowercase letters, digits, and underscores."
    )
    return .function(
        ResponsesApiTool(
            name: "spawn_agent",
            description: spawnAgentToolDescriptionV2(
                availableModelsDescription: availableModelsDescription,
                inheritedModelGuidance: inheritedModelGuidance,
                usageHintText: options.usageHintText,
                description: descriptionOverride
            ),
            strict: false,
            parameters: .object(
                properties,
                required: ["task_name", "message"],
                additionalProperties: false
            ),
            outputSchema: spawnAgentOutputSchemaV2(hideAgentMetadata: options.hideAgentTypeModelReasoning)
        )
    )
}

func createSendInputToolV1() -> ToolSpec {
    let properties: [String: JsonSchema] = [
        "target": .string("Agent id to message (from spawn_agent)."),
        "message": .string("Legacy plain-text message to send to the agent. Use either message or items."),
        "items": createCollabInputItemsSchema(),
        "interrupt": .boolean(
            "True interrupts the current task and handles this message immediately; false or omitted queues it."
        ),
    ]
    return .namespace(
        ResponsesApiNamespace(
            name: MULTI_AGENT_V1_NAMESPACE,
            description: MULTI_AGENT_V1_NAMESPACE_DESCRIPTION,
            tools: [
                ResponsesApiNamespaceTool(
                    function: ResponsesApiTool(
                        name: "send_input",
                        description:
                            "Send a message to an existing agent. Use interrupt=true to redirect work immediately. You should reuse the agent by send_input if you believe your assigned task is highly dependent on the context of a previous task.",
                        strict: false,
                        parameters: .object(properties, required: ["target"], additionalProperties: false),
                        outputSchema: sendInputOutputSchema()
                    )
                )
            ]
        )
    )
}

func createSendMessageTool() -> ToolSpec {
    let properties: [String: JsonSchema] = [
        "target": .string("Relative or canonical task name to message (from spawn_agent)."),
        "message": .string("Message text to queue on the target agent."),
    ]
    return .function(
        ResponsesApiTool(
            name: "send_message",
            description:
                "Send a message to an existing agent. The message will be delivered promptly. Does not trigger a new turn.",
            strict: false,
            parameters: .object(
                properties,
                required: ["target", "message"],
                additionalProperties: false
            )
        )
    )
}

func createFollowupTaskTool() -> ToolSpec {
    let properties: [String: JsonSchema] = [
        "target": .string(
            "Agent id or canonical task name to send a follow-up task to (from spawn_agent)."
        ),
        "message": .string("Message text to send to the target agent."),
    ]
    return .function(
        ResponsesApiTool(
            name: "followup_task",
            description:
                "Send a follow-up task to an existing non-root target agent and trigger a turn if it is idle. If the target is already running, deliver the task promptly at message boundaries while sampling, or after the pending tool call completes.",
            strict: false,
            parameters: .object(
                properties,
                required: ["target", "message"],
                additionalProperties: false
            )
        )
    )
}

func createResumeAgentTool() -> ToolSpec {
    return .namespace(
        ResponsesApiNamespace(
            name: MULTI_AGENT_V1_NAMESPACE,
            description: MULTI_AGENT_V1_NAMESPACE_DESCRIPTION,
            tools: [
                ResponsesApiNamespaceTool(
                    function: ResponsesApiTool(
                        name: "resume_agent",
                        description:
                            "Resume a previously closed agent by id so it can receive send_input and wait_agent calls.",
                        strict: false,
                        parameters: .object(
                            ["id": .string("Agent id to resume.")],
                            required: ["id"],
                            additionalProperties: false
                        ),
                        outputSchema: resumeAgentOutputSchema()
                    )
                )
            ]
        )
    )
}

func createWaitAgentToolV1(_ options: WaitAgentTimeoutOptions = WaitAgentTimeoutOptions()) -> ToolSpec {
    .namespace(
        ResponsesApiNamespace(
            name: MULTI_AGENT_V1_NAMESPACE,
            description: MULTI_AGENT_V1_NAMESPACE_DESCRIPTION,
            tools: [
                ResponsesApiNamespaceTool(
                    function: ResponsesApiTool(
                        name: "wait_agent",
                        description:
                            "Wait for agents to reach a final status. Completed statuses may include the agent's final message. Returns empty status when timed out. Once the agent reaches a final status, a notification message will be received containing the same completed status.",
                        strict: false,
                        parameters: waitAgentToolParametersV1(options),
                        outputSchema: waitOutputSchemaV1()
                    )
                )
            ]
        )
    )
}

func createWaitAgentToolV2(_ options: WaitAgentTimeoutOptions = WaitAgentTimeoutOptions()) -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: "wait_agent",
            description:
                "Wait for a mailbox update from any live agent, including queued messages and final-status notifications. The wait also ends early when new user input is steered into the active turn. Does not return the content; returns either a summary of which agents have updates (if any), an interruption summary for steered input, or a timeout summary if no activity arrives before the deadline.",
            strict: false,
            parameters: waitAgentToolParametersV2(options),
            outputSchema: waitOutputSchemaV2()
        )
    )
}

func createListAgentsTool() -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: "list_agents",
            description:
                "List live agents in the current root thread tree. Optionally filter by task-path prefix.",
            strict: false,
            parameters: .object(
                [
                    "path_prefix": .string(
                        "Task-path prefix filter without a trailing slash. Omit to list all live agents."
                    )
                ],
                additionalProperties: false
            ),
            outputSchema: listAgentsOutputSchema()
        )
    )
}

func createCloseAgentToolV1() -> ToolSpec {
    .namespace(
        ResponsesApiNamespace(
            name: MULTI_AGENT_V1_NAMESPACE,
            description: MULTI_AGENT_V1_NAMESPACE_DESCRIPTION,
            tools: [
                ResponsesApiNamespaceTool(
                    function: ResponsesApiTool(
                        name: "close_agent",
                        description:
                            "Close an agent and any open descendants when they are no longer needed, and return the target agent's previous status before shutdown was requested. Completed agents remain open and count toward the concurrency limit until closed. Don't keep agents open for too long if they are not needed anymore.",
                        strict: false,
                        parameters: .object(
                            ["target": .string("Agent id to close (from spawn_agent).")],
                            required: ["target"],
                            additionalProperties: false
                        ),
                        outputSchema: agentPreviousStatusOutputSchema(
                            "The agent status observed before shutdown was requested."
                        )
                    )
                )
            ]
        )
    )
}

func createInterruptAgentToolV2() -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: "interrupt_agent",
            description:
                "Interrupt an agent's current turn, if any, and return its previous status. The agent remains available for messages and follow-up tasks.",
            strict: false,
            parameters: .object(
                [
                    "target": .string(
                        "Agent id or canonical task name to interrupt (from spawn_agent)."
                    )
                ],
                required: ["target"],
                additionalProperties: false
            ),
            outputSchema: agentPreviousStatusOutputSchema(
                "The agent status observed before the interrupt request was handled."
            )
        )
    )
}

func createCollabInputItemsSchema() -> JsonSchema {
    .array(
        .object(
            [
                "type": .string(
                    "Input item type: text, image, local_image, audio, local_audio, skill, or mention."
                ),
                "text": .string("Text content when type is text."),
                "image_url": .string("Image URL when type is image."),
                "audio_url": .string("Audio data URL when type is audio."),
                "path": .string(
                    "Path when type is local_image/local_audio/skill, or structured mention target such as app://<connector-id> or plugin://<plugin-name>@<marketplace-name> when type is mention."
                ),
                "name": .string("Display name when type is skill or mention."),
            ],
            additionalProperties: false
        ),
        description:
            "Structured input items. Use this to pass explicit mentions (for example app:// connector paths)."
    )
}

func spawnAgentCommonPropertiesV1(_ agentTypeDescription: String) -> [String: JsonSchema] {
    [
        "message": .string("Initial plain-text task for the new agent. Use either message or items."),
        "items": createCollabInputItemsSchema(),
        "agent_type": .string("\(SPAWN_AGENT_TYPE_OVERRIDE_DESCRIPTION_V1)\n\(agentTypeDescription)"),
        "fork_context": .boolean(
            "True forks the current thread history into the new agent; false or omitted starts with only the initial prompt."
        ),
        "model": .string(SPAWN_AGENT_MODEL_OVERRIDE_DESCRIPTION),
        "reasoning_effort": .string(
            "Reasoning effort override for the new agent. Omit to inherit the parent effort."
        ),
    ]
}

func spawnAgentCommonPropertiesV2(_ agentTypeDescription: String) -> [String: JsonSchema] {
    [
        "message": .string("Initial plain-text task for the new agent."),
        "agent_type": .string(
            "Agent type override for the new agent. Omit unless explicitly asked. The selected role applies regardless of how much parent history is inherited.\n\(agentTypeDescription)"
        ),
        "fork_turns": .string(
            "Optional number of turns to fork. Defaults to `all`. Use `none`, `all`, or a positive integer string such as `3` to fork only the most recent turns."
        ),
        "model": .string(SPAWN_AGENT_MODEL_OVERRIDE_DESCRIPTION),
        "reasoning_effort": .string(
            "Reasoning effort override for the new agent. Omit to inherit the parent effort."
        ),
    ]
}

func hideSpawnAgentMetadataOptions(_ properties: inout [String: JsonSchema]) {
    properties.removeValue(forKey: "agent_type")
    properties.removeValue(forKey: "model")
    properties.removeValue(forKey: "reasoning_effort")
}

func spawnAgentToolDescription(
    availableModelsDescription: String?,
    inheritedModelGuidance: String?,
    returnValueDescription: String,
    usageHintText: String?
) -> String {
    let agentRoleGuidance = availableModelsDescription ?? ""
    let inherited = inheritedModelGuidance ?? ""
    let toolDescription = """

            \(agentRoleGuidance)
            Spawn a sub-agent for a well-scoped task. \(returnValueDescription) \(inherited)
        """
    if let usageHintText {
        return """

            \(toolDescription)
        \(usageHintText)
        """
    }
    let agentRoleUsageHint = availableModelsDescription == nil
        ? ""
        : "Agent-role guidance below only helps choose which agent to use after spawning is already authorized; it never authorizes spawning by itself."
    return """

            \(toolDescription)
        This spawn_agent tool provides you access to sub-agents that inherit your current model by default. Do not set the `model` field unless the user explicitly asks for a different model. You should follow the rules and guidelines below to use this tool.

        Do not spawn sub-agents unless the user or applicable AGENTS.md/skill instructions explicitly ask for sub-agents, delegation, or parallel agent work.
        Requests for depth, thoroughness, research, investigation, or detailed codebase analysis do not count as permission to spawn.
        \(agentRoleUsageHint)

        ### When to delegate vs. do the subtask yourself
        - First, quickly analyze the overall user task and form a succinct high-level plan. Identify which tasks are immediate blockers on the critical path, and which tasks are sidecar tasks that are needed but can run in parallel without blocking the next local step. As part of that plan, explicitly decide what immediate task you should do locally right now. Do this planning step before delegating to agents so you do not hand off the immediate blocking task to a submodel and then waste time waiting on it.
        - Use a subagent when a subtask is easy enough for it to handle and can run in parallel with your local work. Prefer delegating concrete, bounded sidecar tasks that materially advance the main task without blocking your immediate next local step.
        - Do not delegate urgent blocking work when your immediate next step depends on that result. If the very next action is blocked on that task, the main rollout should usually do it locally to keep the critical path moving.
        - Keep work local when the subtask is too difficult to delegate well and when it is tightly coupled, urgent, or likely to block your immediate next step.

        ### Designing delegated subtasks
        - Subtasks must be concrete, well-defined, and self-contained.
        - Delegated subtasks must materially advance the main task.
        - Do not duplicate work between the main rollout and delegated subtasks.
        - Avoid issuing multiple delegate calls on the same unresolved thread unless the new delegated task is genuinely different and necessary.
        - Narrow the delegated ask to the concrete output you need next.
        - For coding tasks, prefer delegating concrete code-change worker subtasks over read-only explorer analysis when the subagent can make a bounded patch in a clear write scope.
        - When delegating coding work, instruct the submodel to edit files directly in its forked workspace and list the file paths it changed in the final answer.
        - For code-edit subtasks, decompose work so each delegated task has a disjoint write set.

        ### After you delegate
        - Call wait_agent very sparingly. Only call wait_agent when you need the result immediately for the next critical-path step and you are blocked until it returns.
        - Do not redo delegated subagent tasks yourself; focus on integrating results or tackling non-overlapping work.
        - While the subagent is running in the background, do meaningful non-overlapping work immediately.
        - Do not repeatedly wait by reflex.
        - When a delegated coding task returns, quickly review the uploaded changes, then integrate or refine them.

        ### Parallel delegation patterns
        - Run multiple independent information-seeking subtasks in parallel when you have distinct questions that can be answered independently.
        - Split implementation into disjoint codebase slices and spawn multiple agents for them in parallel when the write scopes do not overlap.
        - Delegate verification only when it can run in parallel with ongoing implementation and is likely to catch a concrete risk before final integration.
        - The key is to find opportunities to spawn multiple independent subtasks in parallel within the same round, while ensuring each subtask is well-defined, self-contained, and materially advances the main task.
        """
}

func spawnAgentToolDescriptionV2(
    availableModelsDescription: String?,
    inheritedModelGuidance: String?,
    usageHintText: String?,
    description: String?
) -> String {
    let agentRoleGuidance = availableModelsDescription ?? ""
    let inherited = inheritedModelGuidance ?? ""
    let toolDescription: String
    if let description {
        toolDescription = """

            \(agentRoleGuidance)
            \(description)
        \(inherited)
        """
    } else {
        toolDescription = """

            \(agentRoleGuidance)
            Spawns an agent to work on the specified task. If your current task is `/root/task1` and you spawn_agent with task_name "task_3" the agent will have canonical task name `/root/task1/task_3`.
        You are then able to refer to this agent as `task_3` or `/root/task1/task_3` interchangeably. However an agent `/root/task2/task_3` would only be able to communicate with this agent via its canonical name `/root/task1/task_3`.
        The spawned agent will have the same tools as you and the ability to spawn its own subagents.
        \(inherited)
        It will be able to send you and other running agents messages, and its final answer will be provided to you when it finishes.
        The new agent's canonical task name will be provided to it along with the message.

        Note that passing `fork_turns="none"` will not pass any surrounding context to the spawned subagent, which may cause the agent to lack the context it needs to complete its task, whereas `fork_turns="all"` will provide the subagent with all surrounding context.
        """
    }
    if let usageHintText {
        return """

            \(toolDescription)
        \(usageHintText)
        """
    }
    return toolDescription
}

func spawnAgentModelsDescription(
    _ models: [ModelPreset],
    _ multiAgentVersion: MultiAgentVersion
) -> String {
    let visible = models
        .filter(\.showInPicker)
        .filter { modelSupportsMultiAgentBackend($0, multiAgentVersion: multiAgentVersion) }
        .prefix(MAX_SPAWN_AGENT_MODEL_OVERRIDES)
    if visible.isEmpty {
        return "No picker-visible model overrides are currently loaded."
    }
    let modelDescriptions = visible.map { model in
        let efforts = model.supportedReasoningEfforts.map { preset in
            var effort = preset.effort.asStr
            if effort.count > MAX_REASONING_EFFORT_CHARS_IN_SPAWN_AGENT_DESCRIPTION {
                effort = String(effort.prefix(MAX_REASONING_EFFORT_CHARS_IN_SPAWN_AGENT_DESCRIPTION))
            }
            if preset.effort == model.defaultReasoningEffort {
                return "\(effort) (default)"
            }
            return effort
        }.joined(separator: ", ")
        let reasoningSuffix = efforts.isEmpty ? "" : " Reasoning efforts: \(efforts)."
        let serviceTiers = model.serviceTiers.map(\.id).joined(separator: ", ")
        let serviceSuffix = serviceTiers.isEmpty ? "" : " Service tiers: \(serviceTiers)."
        return "- `\(model.model)`: \(model.description)\(reasoningSuffix)\(serviceSuffix)"
    }.joined(separator: "\n")
    return "Available model overrides (optional; inherited parent model is preferred):\n\(modelDescriptions)"
}

func waitAgentToolParametersV1(_ options: WaitAgentTimeoutOptions) -> JsonSchema {
    .object(
        [
            "targets": .array(
                .string(),
                description: "Agent ids to wait on. Pass multiple ids to wait for whichever finishes first."
            ),
            "timeout_ms": .number(
                "Timeout in milliseconds. Defaults to \(options.defaultTimeoutMs), min \(options.minTimeoutMs), max \(options.maxTimeoutMs). Prefer longer waits (minutes) to avoid busy polling."
            ),
        ],
        required: ["targets"],
        additionalProperties: false
    )
}

func waitAgentToolParametersV2(_ options: WaitAgentTimeoutOptions) -> JsonSchema {
    .object(
        [
            "timeout_ms": .number(
                "Timeout in milliseconds. Defaults to \(options.defaultTimeoutMs), min \(options.minTimeoutMs), max \(options.maxTimeoutMs)."
            )
        ],
        additionalProperties: false
    )
}

func agentStatusOutputSchema() -> HarnessJSON {
    .object([
        "oneOf": .array([
            .object([
                "type": .string("string"),
                "enum": .array([
                    .string("pending_init"), .string("running"), .string("interrupted"),
                    .string("shutdown"), .string("not_found"),
                ]),
            ]),
            .object([
                "type": .string("object"),
                "properties": .object(["completed": .object(["type": .array([.string("string"), .string("null")])])]),
                "required": .array([.string("completed")]),
                "additionalProperties": .bool(false),
            ]),
            .object([
                "type": .string("object"),
                "properties": .object(["errored": .object(["type": .string("string")])]),
                "required": .array([.string("errored")]),
                "additionalProperties": .bool(false),
            ]),
        ])
    ])
}

func spawnAgentOutputSchemaV1() -> HarnessJSON {
    jsonSchemaObject(
        [
            "agent_id": jsonProperty(type: "string", description: "Thread identifier for the spawned agent."),
            "nickname": jsonProperty(
                types: ["string", "null"],
                description: "User-facing nickname for the spawned agent when available."
            ),
        ],
        required: ["agent_id", "nickname"]
    )
}

func spawnAgentOutputSchemaV2(hideAgentMetadata: Bool) -> HarnessJSON {
    if hideAgentMetadata {
        return jsonSchemaObject(
            [
                "task_name": jsonProperty(
                    type: "string",
                    description: "Canonical task name for the spawned agent."
                )
            ],
            required: ["task_name"]
        )
    }
    return jsonSchemaObject(
        [
            "task_name": jsonProperty(
                type: "string",
                description: "Canonical task name for the spawned agent."
            ),
            "nickname": jsonProperty(
                types: ["string", "null"],
                description: "User-facing nickname for the spawned agent when available."
            ),
        ],
        required: ["task_name", "nickname"]
    )
}

func sendInputOutputSchema() -> HarnessJSON {
    jsonSchemaObject(
        [
            "submission_id": jsonProperty(
                type: "string",
                description: "Identifier for the queued input submission."
            )
        ],
        required: ["submission_id"]
    )
}

func listAgentsOutputSchema() -> HarnessJSON {
    jsonSchemaObject(
        [
            "agents": .object([
                "type": .string("array"),
                "items": jsonSchemaObject(
                    [
                        "agent_name": jsonProperty(
                            type: "string",
                            description:
                                "Canonical task name for the agent when available, otherwise the agent id."
                        ),
                        "agent_status": .object([
                            "description": .string("Last known status of the agent."),
                            "allOf": .array([agentStatusOutputSchema()]),
                        ]),
                    ],
                    required: ["agent_name", "agent_status"]
                ),
                "description": .string("Live agents visible in the current root thread tree."),
            ])
        ],
        required: ["agents"]
    )
}

func resumeAgentOutputSchema() -> HarnessJSON {
    jsonSchemaObject(["status": agentStatusOutputSchema()], required: ["status"])
}

func waitOutputSchemaV1() -> HarnessJSON {
    jsonSchemaObject(
        [
            "status": .object([
                "type": .string("object"),
                "description": .string("Final statuses keyed by agent id."),
                "additionalProperties": agentStatusOutputSchema(),
            ]),
            "timed_out": jsonProperty(
                type: "boolean",
                description:
                    "Whether the wait call returned due to timeout before any agent reached a final status."
            ),
        ],
        required: ["status", "timed_out"]
    )
}

func waitOutputSchemaV2() -> HarnessJSON {
    jsonSchemaObject(
        [
            "message": jsonProperty(
                type: "string",
                description:
                    "Brief wait summary without the agent's final content, including any timeout adjustment."
            ),
            "timed_out": jsonProperty(
                type: "boolean",
                description:
                    "Whether the wait call returned because no mailbox update arrived before the timeout."
            ),
        ],
        required: ["message", "timed_out"]
    )
}

func agentPreviousStatusOutputSchema(_ previousStatusDescription: String) -> HarnessJSON {
    jsonSchemaObject(
        [
            "previous_status": .object([
                "description": .string(previousStatusDescription),
                "allOf": .array([agentStatusOutputSchema()]),
            ])
        ],
        required: ["previous_status"]
    )
}

func jsonSchemaObject(_ properties: [String: HarnessJSON], required: [String]) -> HarnessJSON {
    .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
        "additionalProperties": .bool(false),
    ])
}

func jsonProperty(type: String, description: String) -> HarnessJSON {
    .object(["type": .string(type), "description": .string(description)])
}

func jsonProperty(types: [String], description: String) -> HarnessJSON {
    .object(["type": .array(types.map { .string($0) }), "description": .string(description)])
}
