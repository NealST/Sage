//
//  mcp_openai_file.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_openai_file.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Upload clients wait for Phase 6. This keeps the file-id type.
//

import Foundation

public struct McpOpenAIFile: Equatable, Sendable {
    public var fileId: String
    public var filename: String?

    public init(fileId: String, filename: String? = nil) {
        self.fileId = fileId
        self.filename = filename
    }
}
