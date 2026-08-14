//
//  SkillAuthoring.swift
//  Sage
//
//  Shared skill-writing guidance used by `save_skill` and enhance composition.
//

import Foundation

nonisolated enum SkillAuthoring {
    /// Guidance for the skill `description` field (frontmatter / catalog).
    static let descriptionGuidelines = """
    Use imperative phrasing: "Use this skill when..." \
    Focus on user intent, not implementation. Be specific about when the skill applies, \
    including non-obvious triggers. Max 1024 characters.
    """

    /// Guidance for the skill markdown body (mirrors `save_skill` body parameter).
    static let bodyGuidelines = """
    (1) Add what the agent lacks, omit what it knows — focus on project-specific conventions, \
    non-obvious edge cases, and specific tools/APIs. \
    (2) Favor procedures over declarations — teach how to approach a class of problems. \
    (3) Include a Gotchas section for environment-specific facts that defy assumptions. \
    (4) Provide defaults, not menus — pick a recommended approach, mention alternatives briefly. \
    (5) Use templates for output format, checklists for multi-step workflows. \
    (6) Keep under 500 lines. Move detailed references to separate files if needed. \
    (7) Do NOT include frontmatter — it will be added automatically.
    """
}
