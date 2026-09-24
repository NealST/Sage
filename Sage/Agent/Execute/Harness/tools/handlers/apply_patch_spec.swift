//
//  apply_patch_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/apply_patch_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Sage exposes apply_patch as a JSON function tool (not a freeform grammar).
//  The patch body itself stays the Codex apply-patch language.
//

import Foundation

enum ApplyPatchSpec {
    static let toolName = "apply_patch"

    static let description = """
        Edit files with a structured patch. Prefer this over write_text_file when \
        changing existing repository files — send hunks, not the whole file. \
        Use write_text_file only for new short files or non-patch config. \
        Shell is for build, test, git, and other non-file CLI work.

        The `input` value must be a complete apply_patch document:

        *** Begin Patch
        *** Add File: path/new.txt
        +hello
        *** Update File: path/existing.txt
        @@
         context
        -old
        +new
        *** Delete File: path/gone.txt
        *** End Patch

        Update hunks need enough context to locate uniquely. If context does not \
        match, the tool fails with an actionable error and does not rewrite the file.
        """

    static let definition = ToolDefinition(
        name: toolName,
        description: description,
        parameters: .schemaObject(
            properties: [
                "input": .stringProperty(
                    "Complete apply_patch document, including *** Begin Patch and *** End Patch."
                ),
            ],
            required: ["input"]
        )
    )
}
