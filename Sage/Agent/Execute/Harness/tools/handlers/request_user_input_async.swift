//
//  request_user_input_async.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/request_user_input_async.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session turn-item emission waits for Phase 5. The handler validates
//  questions and invokes onRequestUserInputAsync.
//

import CodexCore
import CodexProtocol
import Foundation

let REQUEST_USER_INPUT_ASYNC_TOOL_NAME = "request_user_input_async"

struct RequestUserInputAsyncArgs: Decodable {
    var questions: [AsyncUserInputQuestion]
}

struct RequestUserInputAsyncHandler: CoreToolRuntime {
    var descriptionText: String
    var parametersOverride: String?

    init(
        description: String = "Ask the user one or more questions without blocking the turn.",
        parameters: String? = nil
    ) {
        self.descriptionText = description
        self.parametersOverride = parameters
    }

    func toolName() -> ToolName { ToolName(plain: REQUEST_USER_INPUT_ASYNC_TOOL_NAME) }
    func isBuiltinControlTool() -> Bool { true }

    func spec() -> ToolSpec {
        var options = JsonSchema.array(
            .string(),
            description: "Suggested answers, in display order. Put the recommended answer first; the first option is preselected by default. The user can select one option or enter a free-text answer. Do not include an Other option or a free-text placeholder; the UI provides free-text input automatically. Omit options for a free-text-only question."
        )
        options.minItems = 1
        let question = JsonSchema.object(
            [
                "title": .string(
                    "The complete question shown to the user, including any context needed to answer it."
                ),
                "options": options,
            ],
            required: ["title"],
            additionalProperties: false
        )
        var questions = JsonSchema.array(
            question,
            description: "One or more self-contained questions to present together, in display order."
        )
        questions.minItems = 1
        var parameters = JsonSchema.object(
            ["questions": questions],
            required: ["questions"],
            additionalProperties: false
        )
        if let override = parametersOverride {
            do {
                parameters = try parseCatalogParameters(override)
            } catch {
                // Keep bundled parameters when the catalog override is invalid.
            }
        }
        return .function(
            ResponsesApiTool(
                name: REQUEST_USER_INPUT_ASYNC_TOOL_NAME,
                description: descriptionText,
                strict: false,
                parameters: parameters
            )
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "\(REQUEST_USER_INPUT_ASYNC_TOOL_NAME) handler received unsupported payload"
            )
        }
        let args: RequestUserInputAsyncArgs = try parseArguments(arguments)
        if args.questions.isEmpty {
            throw FunctionCallError.respondToModel("questions must not be empty")
        }
        for question in args.questions {
            if question.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FunctionCallError.respondToModel("question titles must not be empty")
            }
            if let options = question.options,
               options.isEmpty || options.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw FunctionCallError.respondToModel(
                    "options must contain at least one non-empty answer"
                )
            }
        }
        invocation.onRequestUserInputAsync?(args.questions)
        return boxedToolOutput(FunctionToolOutput.fromText(#"{"accepted":true}"#, success: true))
    }
}
