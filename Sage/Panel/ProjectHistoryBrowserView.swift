//
//  ProjectHistoryBrowserView.swift
//  Sage
//
//  Browse-only recent git commits.
//

import SwiftUI

struct ProjectHistoryBrowserView: View {
    let rootURL: URL

    @Environment(\.sageTypography) private var type
    @State private var commits: [GitCommitSummary] = []
    @State private var hasGit = false

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
                List(commits) { commit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.subject)
                            .font(.system(size: type.body))
                            .lineLimit(2)
                        Text(commit.shortHash)
                            .font(.system(size: type.micro, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: rootURL.path) {
            let root = rootURL
            let loaded = await Task.detached(priority: .utility) {
                (
                    GitBranchReader.isGitRepository(root),
                    GitBranchReader.recentCommits(inProjectRoot: root)
                )
            }.value
            hasGit = loaded.0
            commits = loaded.1
        }
    }
}
