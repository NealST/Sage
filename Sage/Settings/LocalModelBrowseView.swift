//
//  LocalModelBrowseView.swift
//  Sage
//
//  Hugging Face browse/download sheet: curated MLX picks, Hub search, and
//  manual repo-id entry. Download progress is determinate (HIG loading:
//  known-length waits show how far along they are) and cancellable.
//

import SwiftUI

struct LocalModelBrowseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sageTypography) private var type

    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    /// Distinguishes "no results for this query" from "nothing searched yet".
    @State private var hasCompletedSearch = false
    @State private var searchResults: [ModelCatalog.HubModelSearchResult] = []
    @State private var manualRepoDraft = ""

    private var catalog: ModelCatalog { .shared }

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                featuredSection
                searchResultsSection
                manualSection
            }
            .listStyle(.inset)
            .sageScrollEdgeGlass()
            .safeAreaInset(edge: .top, spacing: 0) {
                SageInlineSearchField(
                    prompt: "Search mlx-community models",
                    text: $searchText
                )
                .padding(.horizontal, SageDesign.Spacing.large)
                .padding(.vertical, SageDesign.Spacing.small)
            }

            footer
        }
        .onExitCommand { dismiss() }
        .onChange(of: searchText) { _, query in
            scheduleSearch(query)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    /// Debounced Hub search — each keystroke restarts the timer so only the
    /// settled query hits the network.
    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            isSearching = false
            hasCompletedSearch = false
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true
            let results = await catalog.searchHubModels(query)
            guard !Task.isCancelled else { return }
            isSearching = false
            hasCompletedSearch = true
            searchResults = results
        }
    }

    private var header: some View {
        HStack {
            Text("Hugging Face Models")
                .sageFont(type.title, weight: .semibold)
            Spacer()
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(
                "Weights download from huggingface.co (or the CN mirror when faster) and run entirely on this Mac."
            )
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    // MARK: - Featured

    private var featuredSection: some View {
        Section("Featured") {
            ForEach(ModelCatalog.featuredModels) { model in
                repoRow(repoID: model.repoID, subtitle: model.summary)
            }
        }
    }

    // MARK: - Search

    private var searchResultsSection: some View {
        Section("Results") {
            if isSearching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Searching…")
                        .sageFont(type.caption)
                        .foregroundStyle(.secondary)
                }
            } else if isQuerying {
                ForEach(searchResults) { result in
                    repoRow(repoID: result.repoID, subtitle: searchSubtitle(result))
                }
            } else if hasCompletedSearch {
                Text("No models found for “\(trimmedQuery)”.")
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Search mlx-community for more builds, or add a repo ID below.")
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isQuerying: Bool {
        let query = trimmedQuery
        return !query.isEmpty && !searchResults.isEmpty
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchSubtitle(_ result: ModelCatalog.HubModelSearchResult) -> String {
        var parts: [String] = []
        if let downloads = result.downloads {
            parts.append("\(downloads.formatted(.number.notation(.compactName))) downloads")
        }
        if let likes = result.likes {
            parts.append("\(likes.formatted(.number.notation(.compactName))) likes")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Manual repo entry

    private var manualSection: some View {
        Section("Add by Repo ID") {
            HStack(spacing: SageDesign.Spacing.small) {
                TextField("mlx-community/Qwen3-4B-4bit", text: $manualRepoDraft)
                    .onSubmit(downloadManualRepo)
                Button("Download", action: downloadManualRepo)
                    .disabled(!isValidRepoID(trimmedManualDraft))
            }
            if !trimmedManualDraft.isEmpty && !isValidRepoID(trimmedManualDraft) {
                Text("Use the org/name form, e.g. mlx-community/Qwen3-4B-4bit")
                    .sageFont(type.caption)
                    .foregroundStyle(SageDesign.Palette.dangerText)
            }
        }
    }

    private var trimmedManualDraft: String {
        manualRepoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidRepoID(_ raw: String) -> Bool {
        raw.contains("/")
    }

    private func downloadManualRepo() {
        let repoID = trimmedManualDraft
        guard isValidRepoID(repoID) else { return }
        catalog.startDownload(repoID: repoID)
        manualRepoDraft = ""
    }

    // MARK: - Rows

    private func repoRow(repoID: String, subtitle: String) -> some View {
        HStack(spacing: SageDesign.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelSelection.local(repoID).displayName)
                    .sageFont(type.body, weight: .semibold)
                Text(subtitle)
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailingControl(for: repoID)
        }
    }

    @ViewBuilder
    private func trailingControl(for repoID: String) -> some View {
        switch catalog.localState(for: repoID) {
        case .notInstalled:
            Button("Download") {
                catalog.startDownload(repoID: repoID)
            }
            .controlSize(.small)

        case .downloading(let progress):
            HStack(spacing: SageDesign.Spacing.small) {
                ProgressView(value: progress)
                    .frame(width: 110)
                Text("\(Int(progress * 100))%")
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Cancel") {
                    catalog.cancelDownload(repoID: repoID)
                }
                .controlSize(.small)
            }

        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .sageFont(type.caption, weight: .medium)
                .foregroundStyle(SageDesign.Palette.successText)
                .labelStyle(.titleAndIcon)

        case .failed(let reason):
            HStack(spacing: SageDesign.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SageDesign.Palette.warningText)
                    .sageHelp(reason)
                Button("Retry") {
                    catalog.startDownload(repoID: repoID)
                }
                .controlSize(.small)
            }
        }
    }
}
