//
//  selection.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/selection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import CodexUtils
import Foundation

/// Supplies ordered skills, disabled identities, and discovery paths for explicit selection.
public protocol ExplicitSkillLookup {
    func skills() -> [SkillMetadata]
    func disabledPaths() -> Set<AbsolutePathBuf>
    func skillDiscoveryPathForPath(_ path: AbsolutePathBuf) -> AbsolutePathBuf?
}

extension ExplicitSkillLookup {
    public func isSkillEnabled(_ skill: SkillMetadata) -> Bool {
        !disabledPaths().contains(skill.pathToSkillsMd)
    }
}

/// Collect explicitly mentioned skills from structured and text mentions.
public func collectExplicitSkillMentions(
    inputs: [UserInput],
    loadedSkills: any ExplicitSkillLookup,
    connectorSlugCounts: [String: Int]
) -> [SkillMetadata] {
    let skillNameCounts = buildSkillNameCounts(
        skills: loadedSkills.skills(),
        disabledPaths: loadedSkills.disabledPaths()
    ).exact

    let selectionContext = SkillSelectionContext(
        loadedSkills: loadedSkills,
        skillNameCounts: skillNameCounts,
        connectorSlugCounts: connectorSlugCounts
    )
    var selected: [SkillMetadata] = []
    var seenNames = Set<String>()
    var seenPaths = Set<AbsolutePathBuf>()
    var blockedPlainNames = Set<String>()

    for input in inputs {
        if case .skill(let name, let path) = input {
            blockedPlainNames.insert(name)
            guard let absolute = try? AbsolutePathBuf.relativeToCurrentDir(path) else {
                continue
            }
            guard let skill = selectionContext.loadedSkills.skills().first(where: { skill in
                skill.pathToSkillsMd == absolute
                    || selectionContext.loadedSkills.skillDiscoveryPathForPath(skill.pathToSkillsMd)
                    == absolute
            }) else {
                continue
            }
            if !selectionContext.loadedSkills.isSkillEnabled(skill)
                || seenPaths.contains(skill.pathToSkillsMd) {
                continue
            }
            seenPaths.insert(skill.pathToSkillsMd)
            seenNames.insert(skill.name)
            selected.append(skill)
        }
    }

    for input in inputs {
        if case .text(let text, _) = input {
            let mentionedNames = extractToolMentions(text)
            selectSkillsFromMentions(
                selectionContext,
                blockedPlainNames: blockedPlainNames,
                mentions: mentionedNames,
                seenNames: &seenNames,
                seenPaths: &seenPaths,
                selected: &selected
            )
        }
    }

    return selected
}

struct SkillSelectionContext {
    var loadedSkills: any ExplicitSkillLookup
    var skillNameCounts: [String: Int]
    var connectorSlugCounts: [String: Int]
}

func selectSkillsFromMentions(
    _ selectionContext: SkillSelectionContext,
    blockedPlainNames: Set<String>,
    mentions: ToolMentions,
    seenNames: inout Set<String>,
    seenPaths: inout Set<AbsolutePathBuf>,
    selected: inout [SkillMetadata]
) {
    if mentions.isEmpty() { return }

    let mentionSkillPaths = Set(
        mentions.paths
            .filter { path in
                switch toolKindForPath(path) {
                case .app, .mcp, .plugin: return false
                default: return true
                }
            }
            .map(normalizeHostSkillPath)
    )

    for skill in selectionContext.loadedSkills.skills() {
        if !selectionContext.loadedSkills.isSkillEnabled(skill)
            || seenPaths.contains(skill.pathToSkillsMd) {
            continue
        }
        let canonicalPath = normalizeHostSkillPath(skill.pathToSkillsMd.toStringLossy)
        let matchesDiscoveryPath = selectionContext.loadedSkills
            .skillDiscoveryPathForPath(skill.pathToSkillsMd)
            .map { mentionSkillPaths.contains(normalizeHostSkillPath($0.toStringLossy)) } ?? false
        if mentionSkillPaths.contains(canonicalPath) || matchesDiscoveryPath {
            seenPaths.insert(skill.pathToSkillsMd)
            seenNames.insert(skill.name)
            selected.append(skill)
        }
    }

    for skill in selectionContext.loadedSkills.skills() {
        if !selectionContext.loadedSkills.isSkillEnabled(skill)
            || seenPaths.contains(skill.pathToSkillsMd) {
            continue
        }
        if blockedPlainNames.contains(skill.name) { continue }
        if !mentions.containsPlainName(skill.name) { continue }

        let skillCount = selectionContext.skillNameCounts[skill.name] ?? 0
        let connectorCount = selectionContext.connectorSlugCounts[skill.name.lowercased()] ?? 0
        if skillCount != 1 || connectorCount != 0 { continue }

        if seenNames.insert(skill.name).inserted {
            seenPaths.insert(skill.pathToSkillsMd)
            selected.append(skill)
        }
    }
}

func normalizeHostSkillPath(_ path: String) -> String {
    normalizeSkillPath(path).replacingOccurrences(of: "\\", with: "/")
}
