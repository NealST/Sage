//
//  schema_loader.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/schema_loader.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Upstream embeds generated JSON Schema fixtures. Those assets are not
//  bundled yet; loading throws until they are copied as SPM resources.
//

import CodexProtocol
import Foundation

public func generatedHookSchemas() throws -> [String: String] {
    throw CodexErr.unsupportedOperation(
        "generated_hook_schemas waits on embedded schema fixtures"
    )
}
