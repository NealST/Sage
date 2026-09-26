//
//  request_user_input_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/request_user_input_spec.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexCore
import CodexProtocol

let REQUEST_USER_INPUT_TOOL_NAME = "request_user_input"

struct RequestUserInputToolArgs: Decodable, Equatable {
    var questions: [RequestUserInputQuestion]
}

func createRequestUserInputTool(_ description: String) -> ToolSpec {
    let optionProps: [String: JsonSchema] = [
        "label": .string("User-facing label (1-5 words)."),
        "description": .string("One short sentence explaining impact/tradeoff if selected."),
    ]
    let optionsSchema = JsonSchema.array(
        .object(optionProps, required: ["label", "description"], additionalProperties: false),
        description: "Provide 2-3 mutually exclusive choices. Put the recommended option first and suffix its label with \"(Recommended)\". Do not include an \"Other\" option in this list; the client will add a free-form \"Other\" option automatically."
    )
    let questionProps: [String: JsonSchema] = [
        "id": .string("Stable identifier for mapping answers (snake_case)."),
        "header": .string("Short header label shown in the UI (12 or fewer chars)."),
        "question": .string("Single-sentence prompt shown to the user."),
        "options": optionsSchema,
    ]
    let questionsSchema = JsonSchema.array(
        .object(
            questionProps,
            required: ["id", "header", "question", "options"],
            additionalProperties: false
        ),
        description: "Questions to show the user. Prefer 1 and do not exceed 3"
    )
    return .function(
        ResponsesApiTool(
            name: REQUEST_USER_INPUT_TOOL_NAME,
            description: description,
            strict: false,
            parameters: .object(
                ["questions": questionsSchema],
                required: ["questions"],
                additionalProperties: false
            )
        )
    )
}

func requestUserInputUnavailableMessage(mode: ModeKind, availableModes: [ModeKind]) -> String? {
    if availableModes.contains(mode) { return nil }
    return "request_user_input is unavailable in \(mode.displayName) mode"
}

func normalizeRequestUserInputToolArgs(
    _ args: RequestUserInputToolArgs
) throws -> RequestUserInputToolArgs {
    if args.questions.contains(where: { $0.options?.isEmpty ?? true }) {
        throw FunctionCallError.respondToModel(
            "request_user_input requires non-empty options for every question"
        )
    }
    var normalized = args
    for index in normalized.questions.indices {
        normalized.questions[index].isOther = true
    }
    return normalized
}

func requestUserInputToolDescription(availableModes: [ModeKind]) -> String {
    "Request user input for one to three short questions and wait for the response. This tool is only available in \(formatAllowedModes(availableModes))."
}

func formatAllowedModes(_ availableModes: [ModeKind]) -> String {
    let names = availableModes.map(\.displayName)
    switch names.count {
    case 0: return "no modes"
    case 1: return "\(names[0]) mode"
    case 2: return "\(names[0]) or \(names[1]) mode"
    default: return "modes: \(names.joined(separator: ","))"
    }
}
