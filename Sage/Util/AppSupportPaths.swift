//
//  AppSupportPaths.swift
//  Sage
//
//  Single root for ~/Library/Application Support/Sage.
//

import Foundation

nonisolated enum AppSupportPaths {
    /// `~/Library/Application Support/Sage`, creating the directory when requested.
    static func sageDirectory(createIfNeeded: Bool = true) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = appSupport.appendingPathComponent("Sage", isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }
        return dir
    }

    static func sqliteDatabaseURL() -> URL {
        sageDirectory().appendingPathComponent("sage.sqlite")
    }

    static func legacyTasksJSONURL() -> URL {
        sageDirectory().appendingPathComponent("tasks.json")
    }

    static func mcpConfigURL() -> URL {
        sageDirectory().appendingPathComponent("mcp.json")
    }

    static func skillStateURL() -> URL {
        sageDirectory().appendingPathComponent("skills-state.json")
    }

    static func userSkillsDirectory(createIfNeeded: Bool = false) -> URL {
        let dir = sageDirectory(createIfNeeded: createIfNeeded)
            .appendingPathComponent("Skills", isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }
        return dir
    }
}
