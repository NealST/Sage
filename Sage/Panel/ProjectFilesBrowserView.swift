//
//  ProjectFilesBrowserView.swift
//  Sage
//
//  Browse-only project file tree (shallow expansion) with git change badges.
//

import AppKit
import SwiftUI

struct ProjectFilesBrowserView: View {
    let rootURL: URL

    @Environment(\.sageTypography) private var type
    @State private var nodes: [FileNode] = []
    @State private var changes: GitWorkingTreeSummary?
    @State private var searchText = ""
    /// Selected file path — enables arrow-key navigation and row highlight.
    @State private var selectedPath: String?

    private var isFiltering: Bool { !searchText.isEmpty }

    /// Flattens matching nodes so search results show as a plain list of paths.
    private var searchResults: [FileNode] {
        guard isFiltering else { return [] }
        return nodes.flatMap { Self.flatten($0, matching: searchText) }
    }

    private static func flatten(_ node: FileNode, matching query: String) -> [FileNode] {
        var result: [FileNode] = []
        if node.name.localizedCaseInsensitiveContains(query) {
            result.append(node)
        }
        for child in node.children ?? [] {
            result += flatten(child, matching: query)
        }
        return result
    }

    var body: some View {
        Group {
            if nodes.isEmpty {
                ContentUnavailableView(
                    "No files yet",
                    systemImage: "folder",
                    description: Text("This project folder is empty.")
                )
            } else if isFiltering, searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selectedPath) {
                    Section {
                        if isFiltering {
                            ForEach(searchResults) { node in
                                fileRow(node, showPath: true)
                            }
                        } else {
                            OutlineGroup(nodes, children: \.children) { node in
                                fileRow(node, showPath: false)
                            }
                        }
                    } header: {
                        changesHeader
                    }
                }
                .listStyle(.sidebar)
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: "Search files"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: rootURL.path) {
            let root = rootURL
            let loaded = await Task.detached(priority: .utility) {
                (
                    FileNode.loadChildren(of: root, depth: 2),
                    GitBranchReader.workingTreeStatus(inProjectRoot: root)
                )
            }.value
            nodes = loaded.0
            changes = loaded.1
        }
    }

    private func fileRow(_ node: FileNode, showPath: Bool) -> some View {
        HStack(spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name)
                        .sageFont(type.body)
                        .lineLimit(1)
                    if showPath {
                        Text(relativePath(of: node) ?? node.name)
                            .sageMicro(type.micro)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } icon: {
                Image(systemName: node.isDirectory ? "folder" : "doc")
                    .sageFont(type.icon)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let letter = statusLetter(for: node) {
                Text(letter)
                    .sageMicro(type.micro, design: .monospaced)
                    .foregroundStyle(statusColor(for: letter))
                    .accessibilityLabel(accessibilityName(for: letter))
            }
        }
        .tag(node.id)
        // Single click still selects (List); double click previews the file,
        // mirroring the context-menu actions.
        .onTapGesture(count: 2) {
            if node.isDirectory {
                NSWorkspace.shared.open(node.url)
            } else {
                QuickLookPresenter.shared.preview(url: node.url)
            }
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            if !node.isDirectory {
                Button("Quick Look") {
                    QuickLookPresenter.shared.preview(url: node.url)
                }
            }
            Button("Open") {
                NSWorkspace.shared.open(node.url)
            }
        }
    }

    @ViewBuilder private var changesHeader: some View {
        if let changes, !changes.isClean {
            Text(changeSummaryText(changes))
                .sageMicro(type.micro)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    private func changeSummaryText(_ changes: GitWorkingTreeSummary) -> String {
        var parts: [String] = []
        if changes.counts.modified > 0 { parts.append("\(changes.counts.modified) modified") }
        if changes.counts.added > 0 { parts.append("\(changes.counts.added) added") }
        if changes.counts.deleted > 0 { parts.append("\(changes.counts.deleted) deleted") }
        if changes.counts.untracked > 0 { parts.append("\(changes.counts.untracked) untracked") }
        return parts.joined(separator: " · ")
    }

    private func statusLetter(for node: FileNode) -> String? {
        guard let changes, !changes.isClean else { return nil }
        guard let relative = relativePath(of: node) else { return nil }
        if node.isDirectory {
            return changes.statusLetter(containedInDirectory: relative)
        }
        return changes.pathStatuses[relative]
    }

    private func relativePath(of node: FileNode) -> String? {
        let rootPath = rootURL.path
        guard node.url.path.hasPrefix(rootPath) else { return nil }
        var relative = String(node.url.path.dropFirst(rootPath.count))
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative.isEmpty ? nil : relative
    }

    private func statusColor(for letter: String) -> Color {
        switch letter {
        case "M": return SageDesign.Palette.warning
        case "D": return SageDesign.Palette.danger
        default: return .green
        }
    }

    private func accessibilityName(for letter: String) -> String {
        switch letter {
        case "M": return "Modified"
        case "A": return "Added"
        case "D": return "Deleted"
        default: return "Untracked"
        }
    }
}

nonisolated private struct FileNode: Identifiable, Sendable {
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
