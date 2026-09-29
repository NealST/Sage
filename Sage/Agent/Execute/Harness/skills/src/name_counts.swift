//
//  name_counts.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/name_counts.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexUtils
import Foundation

/// Counts how often each skill name appears (exact and ASCII-lowercase), excluding disabled paths.
public func buildSkillNameCounts(
    skills: [SkillMetadata],
    disabledPaths: Set<AbsolutePathBuf>
) -> (exact: [String: Int], lower: [String: Int]) {
    var exactCounts: [String: Int] = [:]
    var lowerCounts: [String: Int] = [:]
    for skill in skills {
        if disabledPaths.contains(skill.pathToSkillsMd) {
            continue
        }
        exactCounts[skill.name, default: 0] += 1
        lowerCounts[skill.name.lowercased(), default: 0] += 1
    }
    return (exactCounts, lowerCounts)
}
