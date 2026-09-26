//
//  view_image.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/view_image.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filesystem / image-prep / Session events wait for Phase 5–6. The handler
//  validates the path argument and invokes onViewImage.
//

import CodexCore
import CodexProtocol
import Foundation

struct ViewImageArgs: Decodable {
    var path: String
    var detail: String?
    var environmentId: String?

    enum CodingKeys: String, CodingKey {
        case path, detail
        case environmentId = "environment_id"
    }
}

struct ViewImageHandler: CoreToolRuntime {
    var options: ViewImageToolOptions

    init(options: ViewImageToolOptions = ViewImageToolOptions(
        canRequestOriginalImageDetail: false,
        unifiedImageBudget: true,
        includeEnvironmentId: false
    )) {
        self.options = options
    }

    func toolName() -> ToolName { ToolName(plain: viewImageToolName) }
    func spec() -> ToolSpec { createViewImageTool(options) }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "view_image handler received unsupported payload"
            )
        }
        let args: ViewImageArgs = try parseArguments(arguments)
        let path = args.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            throw FunctionCallError.respondToModel("view_image requires a non-empty path")
        }
        guard let onView = invocation.onViewImage else {
            throw FunctionCallError.respondToModel("view_image is not wired (Phase 5 Session)")
        }
        guard let imageURL = await onView(path) else {
            throw FunctionCallError.respondToModel("view_image could not load \(path)")
        }
        var object: [String: HarnessJSON] = ["image_url": .string(imageURL)]
        if !options.unifiedImageBudget {
            object["detail"] = .string(args.detail ?? "high")
        }
        return boxedToolOutput(FunctionToolOutput.fromText(HarnessJSON.object(object).encodedString(), success: true))
    }
}
