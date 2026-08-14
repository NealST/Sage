//
//  ProjectSageLayout.swift
//  Sage
//
//  Ensures the on-disk `.sage` layout for a project root.
//

import Foundation

nonisolated enum ProjectSageLayout {
    /// Idempotently creates `<root>/.sage/skills`. Does not touch `.gitignore`.
    static func ensureLayout(at root: URL) throws {
        let sage = root.appendingPathComponent(".sage", isDirectory: true)
        let skills = sage.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
    }
}
