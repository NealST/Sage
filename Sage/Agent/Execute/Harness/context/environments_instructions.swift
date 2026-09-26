//
//  environments_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/environments_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct EnvironmentsInstructions: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("environments.instructions") }
    public var role: String { "developer" }
    public var openMarker: String { environmentsInstructionsOpenTag }
    public var closeMarker: String { environmentsInstructionsCloseTag }
    public var body: String {
        """

        ## Execution environments
        Execution environments are separate machines or workspaces with their own files, shell, and installed capabilities. `<environment_context>` lists the environments selected for this task.

        An environment marked `starting` is not yet usable. Its files, commands, AGENTS.md instructions, skills, plugins, and MCP tools may become available when startup completes.

        Wait only when the current task needs that environment. Continue using tools that are already available for unrelated work.
        """
    }
}
