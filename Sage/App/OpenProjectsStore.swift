//
//  OpenProjectsStore.swift
//  Sage
//
//  Which project windows were open, in open order — relaunch reopens them so
//  the workspace is remembered rather than reset. Writes happen on open and
//  window-close only, never on quit, so the last state survives termination.
//

import Foundation

@MainActor
final class OpenProjectsStore {
    private let fileURL: URL

    init() {
        fileURL = AppSupportPaths.sageDirectory()
            .appendingPathComponent("open-projects.json")
    }

    func load() -> [UUID] {
        guard let data = try? Data(contentsOf: fileURL),
              let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else { return [] }
        return ids
    }

    /// An empty list is indistinguishable from "no project windows open" —
    /// the file is removed so a relaunch restores nothing.
    func save(_ projectIDs: [UUID]) {
        guard !projectIDs.isEmpty else {
            discard()
            return
        }
        guard let data = try? JSONEncoder().encode(projectIDs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func discard() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
