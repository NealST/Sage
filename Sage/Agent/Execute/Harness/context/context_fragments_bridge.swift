//
//  context_fragments_bridge.swift
//  SageCore
//
//  Sage addition (no codex counterpart).
//
//  Re-exports SageContextFragments types that core previously inlined in
//  `context/mod.rs` (`AdditionalContext*`). The crate-level
//  `ContextualUserFragment` stays qualified so it does not collide with
//  SageCore's world-state protocol.
//

import SageContextFragments
import SageProtocol

public typealias AdditionalContextUserFragment = SageContextFragments.AdditionalContextUserFragment
public typealias AdditionalContextDeveloperFragment = SageContextFragments.AdditionalContextDeveloperFragment
public typealias AnnotatedContent = SageContextFragments.AnnotatedContent
public typealias RenderedFragment = SageContextFragments.RenderedFragment
public typealias RecapPrompt = SageContextFragments.RecapPrompt
public typealias AnsweredQuestion = SageContextFragments.AnsweredQuestion

@discardableResult
public func toAnnotatedContent(_ item: inout ResponseItem) -> [AnnotatedContent]? {
    SageContextFragments.toAnnotatedContent(&item)
}

@discardableResult
public func setAnnotatedContent(
    _ item: inout ResponseItem,
    _ annotatedContent: [AnnotatedContent]
) -> Bool {
    SageContextFragments.setAnnotatedContent(&item, annotatedContent)
}
