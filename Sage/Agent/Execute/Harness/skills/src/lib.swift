//
//  lib.swift
//  SageSkills
//
//  Port of codex-rs/skills/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Sibling files compile into this module. `include_dir!` system-skill
//  assets are not bundled yet; `install_system_skills` throws until they
//  are copied as SPM resources.
//

import SageUtils
import Foundation

let SYSTEM_SKILLS_DIR_NAME = ".system"
let SKILLS_DIR_NAME = "skills"
let SYSTEM_SKILLS_MARKER_FILENAME = ".sage-system-skills.marker"

/// Returns the on-disk cache location for embedded system skills from an absolute SAGE_HOME.
public func systemCacheRootDir(_ sageHome: AbsolutePathBuf) -> AbsolutePathBuf {
    sageHome.join(SKILLS_DIR_NAME).join(SYSTEM_SKILLS_DIR_NAME)
}

/// Installs embedded system skills into `SAGE_HOME/skills/.system`.
public func installSystemSkills(sageHome: AbsolutePathBuf) throws {
    _ = sageHome
    throw IOError.other(
        "install_system_skills waits on embedded skill assets (include_dir)"
    )
}

public struct SystemSkillsError: Error, Equatable, CustomStringConvertible {
    public var action: String
    public var message: String

    public var description: String {
        "io error while \(action): \(message)"
    }
}
