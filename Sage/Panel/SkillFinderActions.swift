//
//  SkillFinderActions.swift
//  Sage
//
//  AppKit Finder helpers for skill folders (kept out of SkillCatalog).
//

import AppKit
import Foundation

enum SkillFinderActions {
    static func openSkillsFolder(scope: SkillScope, projectRoot: URL?) {
        switch scope {
        case .global:
            NSWorkspace.shared.open(SkillPaths.userSkillsDirectory(createIfNeeded: true))
        case .project:
            guard let root = projectRoot else { return }
            NSWorkspace.shared.open(SkillPaths.projectSageSkillsDirectory(root: root, createIfNeeded: true))
        }
    }

    static func revealSkill(_ skill: SkillRecord) {
        let url = URL(fileURLWithPath: skill.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
