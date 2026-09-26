//
//  view_image_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/view_image_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol

struct ViewImageToolOptions: Equatable, Sendable {
    var canRequestOriginalImageDetail: Bool
    var unifiedImageBudget: Bool
    var includeEnvironmentId: Bool
}

func createViewImageTool(_ options: ViewImageToolOptions) -> ToolSpec {
    var properties: [String: JsonSchema] = [
        "path": .string("Local filesystem path to an image file.")
    ]
    if options.canRequestOriginalImageDetail && !options.unifiedImageBudget {
        properties["detail"] = .stringEnum(
            ["high", "original"],
            description: "Image detail level. Defaults to `high`; use `original` to preserve exact resolution."
        )
    }
    if options.includeEnvironmentId {
        properties["environment_id"] = .string(
            "Environment id from <environment_context>. Omit to use the primary environment."
        )
    }
    return .function(
        ResponsesApiTool(
            name: viewImageToolName,
            description: "View a local image file from the filesystem when visual inspection is needed. Use this for images already available on disk.",
            strict: false,
            parameters: .object(properties, required: ["path"], additionalProperties: false),
            outputSchema: viewImageOutputSchema(options)
        )
    )
}

func viewImageOutputSchema(_ options: ViewImageToolOptions) -> HarnessJSON {
    var properties: [String: HarnessJSON] = [
        "image_url": .object([
            "type": .string("string"),
            "description": .string("Data URL for the loaded image."),
        ])
    ]
    var required: [HarnessJSON] = [.string("image_url")]
    if !options.unifiedImageBudget {
        properties["detail"] = .object([
            "type": .string("string"),
            "enum": .array([.string("high"), .string("original")]),
            "description": .string(
                "Image detail hint returned by view_image. Returns `high` for default resized behavior or `original` when original resolution is preserved."
            ),
        ])
        required.append(.string("detail"))
    }
    return .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required),
        "additionalProperties": .bool(false),
    ])
}
