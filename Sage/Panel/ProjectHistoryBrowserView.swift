//
//  ProjectHistoryBrowserView.swift
//  Sage
//
//  Browse-only recent git commits.
//

import AppKit
import SwiftUI

struct ProjectHistoryBrowserView: View {
    let rootURL: URL
    let branch: String?

    @Environment(\.sageTypography) private var type
    @State private var commits: [GitCommitSummary] = []
    @State private var totalCommits: Int?
    @State private var hasGit = false
    @State private var copiedHash: String?
    /// Hash chip currently hovered — underlines to reveal the copy affordance.
    @State private var hoveredHash: String?

    var body: some View {
        Group {
            if !hasGit {
                ContentUnavailableView(
                    "No git repository",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Initialize git in this project to see commit history.")
                )
            } else if commits.isEmpty {
                ContentUnavailableView(
                    "No commits yet",
                    systemImage: "clock",
                    description: Text("This repository doesn’t have any commits.")
                )
            } else {
                List {
                    Section {
                        ForEach(commits) { commit in
                            commitRow(commit)
                                .id(commit.shortHash)
                        }
                    } header: {
                        historyHeader
                    }
                }
                .listStyle(.plain)
                .sageScrollEdgeGlass()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: rootURL.path) {
            let root = rootURL
            let loaded = await Task.detached(priority: .utility) {
                (
                    GitBranchReader.isGitRepository(root),
                    GitBranchReader.recentCommits(inProjectRoot: root),
                    GitBranchReader.commitCount(inProjectRoot: root)
                )
            }.value
            hasGit = loaded.0
            commits = loaded.1
            totalCommits = loaded.2
        }
    }

    private func commitRow(_ commit: GitCommitSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.subject)
                .sageFont(type.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                if copiedHash == commit.shortHash {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                } else {
                    Button {
                        copyHash(commit.shortHash)
                    } label: {
                        Text(commit.shortHash)
                            .sageMicro(type.micro, design: .monospaced)
                            .underline(hoveredHash == commit.shortHash, color: .secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredHash = hovering ? commit.shortHash : nil
                    }
                    .help("Copy short hash")
                    .accessibilityLabel("Copy short hash \(commit.shortHash)")
                }
                Text(commit.author)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(commit.date)
                    .sageMicro(type.micro, design: .monospaced)
            }
            .sageMicro(type.micro)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Short Hash") { copyHash(commit.shortHash) }
            Button("Copy Full Hash") { copyHash(commit.fullHash) }
            Button("Copy Subject") { copyText(commit.subject) }
        }
        .animation(SageDesign.Motion.copiedFeedback, value: copiedHash)
    }

    private func copyHash(_ hash: String) {
        copyText(hash)
        copiedHash = hash
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedHash == hash { copiedHash = nil }
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var historyHeader: some View {
        HStack(spacing: 6) {
            if let branch {
                Image(systemName: "arrow.triangle.branch")
                    .sageFont(type.icon)
                Text(branch)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let totalCommits {
                Text("\(totalCommits) commits")
            }
        }
        .sageMicro(type.micro)
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}
