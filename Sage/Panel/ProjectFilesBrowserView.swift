//
//  ProjectFilesBrowserView.swift
//  Sage
//
//  Browse-only project file tree (shallow expansion).
//

import AppKit
import SwiftUI

struct ProjectFilesBrowserView: View {
    let rootURL: URL

    @Environment(\.sageTypography) private var type
    @State private var nodes: [FileNode] = []

    var body: some View {
        Group {
            if nodes.isEmpty {
                ContentUnavailableView(
                    "No files yet",
                    systemImage: "folder",
                    description: Text("This project folder is empty.")
                )
            } else {
                List(nodes, children: \.children) { node in
                    Label {
                        Text(node.name)
                            .font(.system(size: type.body))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: node.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([node.url])
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: rootURL.path) {
            nodes = await Task.detached(priority: .utility) {
                FileNode.loadChildren(of: rootURL, depth: 2)
            }.value
        }
    }
}

private nonisolated struct FileNode: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [Self]?

    static func loadChildren(of directory: URL, depth: Int) -> [Self] {
        guard depth > 0 else { return [] }
        let skip: Set<String> = [
            ".git", "node_modules", "DerivedData", ".build", "Pods", "xcuserdata",
        ]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return items
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent)
                    == .orderedAscending
            }
            .compactMap { url -> Self? in
                let name = url.lastPathComponent
                if skip.contains(name) { return nil }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                let isDir = values?.isDirectory == true
                let kids: [Self]?
                if isDir {
                    let loaded = loadChildren(of: url, depth: depth - 1)
                    kids = loaded.isEmpty ? nil : loaded
                } else {
                    kids = nil
                }
                return Self(
                    id: url.path,
                    name: name,
                    url: url,
                    isDirectory: isDir,
                    children: kids
                )
            }
    }
}
