//
//  context_fragments_bridge.swift
//  CodexCore
//
//  Sage addition (no codex counterpart).
//
//  Re-exports CodexContextFragments types that core previously inlined in
//  `context/mod.rs` (`AdditionalContext*`). The crate-level
//  `ContextualUserFragment` stays qualified so it does not collide with
//  CodexCore's world-state protocol.
//

import CodexContextFragments
import CodexProtocol

public typealias AdditionalContextUserFragment = CodexContextFragments.AdditionalContextUserFragment
public typealias AdditionalContextDeveloperFragment = CodexContextFragments.AdditionalContextDeveloperFragment
public typealias AnnotatedContent = CodexContextFragments.AnnotatedContent
public typealias RenderedFragment = CodexContextFragments.RenderedFragment
public typealias RecapPrompt = CodexContextFragments.RecapPrompt
public typealias AnsweredQuestion = CodexContextFragments.AnsweredQuestion

@discardableResult
public func toAnnotatedContent(_ item: inout ResponseItem) -> [AnnotatedContent]? {
    CodexContextFragments.toAnnotatedContent(&item)
}

@discardableResult
public func setAnnotatedContent(
    _ item: inout ResponseItem,
    _ annotatedContent: [AnnotatedContent]
) -> Bool {
    CodexContextFragments.setAnnotatedContent(&item, annotatedContent)
}
