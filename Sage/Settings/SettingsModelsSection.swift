//
//  SettingsModelsSection.swift
//  Sage
//
//  The Models pane: default + per-phase model selection, the cloud catalog,
//  and local (MLX) downloads. Connection keeps transport-layer fields; this
//  pane owns which models run.
//

import SwiftUI

struct SettingsModelsSection: View {
    @Bindable var settings: ModelSettings
    @Environment(\.sageTypography) private var type

    @State private var browsePresented = false
    @State private var customModelDraft = ""
    /// Repo ID awaiting delete confirmation (nil = dialog closed).
    @State private var pendingDeleteRepoID: String?

    private var catalog: ModelCatalog { .shared }

    var body: some View {
        Group {
            defaultModelSection
            phaseModelsSection
            cloudModelsSection
            localModelsSection
        }
        .sheet(isPresented: $browsePresented) {
            LocalModelBrowseView()
                .frame(minWidth: 560, idealWidth: 640, minHeight: 460, idealHeight: 560)
                .sageScaledTypography()
                .sageAccessibilityObservation()
                .environment(AccessibilitySettings.shared)
        }
        .confirmationDialog(
            pendingDeleteTitle,
            isPresented: deleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let repoID = pendingDeleteRepoID {
                    catalog.deleteModel(repoID: repoID)
                }
                pendingDeleteRepoID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRepoID = nil
            }
        } message: {
            Text("The downloaded weights are removed from disk. You can download them again later.")
        }
        .onAppear {
            catalog.refreshInstalledModels()
            Task { await catalog.refreshCloudModels() }
        }
        .onChange(of: trackedSelections) { oldSelections, newSelections in
            // Warm only the selection that actually changed — re-warming the
            // whole list on every edit would swap multi-GB weights needlessly.
            for (old, new) in zip(oldSelections, newSelections) {
                guard let new, new.origin == .local, new != old else { continue }
                new.warmUpLocalEngineIfApplicable()
            }
        }
    }

    /// All four selections in one Equatable array — one onChange covers the
    /// whole pane.
    private var trackedSelections: [ModelSelection?] {
        [
            settings.defaultSelection,
            settings.planSelection,
            settings.executeSelection,
            settings.reviewSelection,
        ]
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteRepoID != nil },
            set: { shown in
                if !shown { pendingDeleteRepoID = nil }
            }
        )
    }

    private var pendingDeleteTitle: String {
        if let repoID = pendingDeleteRepoID {
            return "Delete “\(ModelSelection.local(repoID).displayName)”?"
        }
        return ""
    }

    // MARK: - Default model

    private var defaultModelSection: some View {
        Section {
            Picker("Default Model", selection: $settings.defaultSelection) {
                selectionOptions(
                    current: settings.defaultSelection,
                    tag: { $0 }
                )
            }
            .pickerStyle(.menu)
        } header: {
            Text("Default Model")
        } footer: {
            Text(
                "Phases without their own model follow this default. Cloud models run on your provider; local models run on-device via MLX — no API key or network needed."
            )
        }
    }

    // MARK: - Phase models

    private var phaseModelsSection: some View {
        Section {
            phasePicker("Plan", selection: $settings.planSelection)
            phasePicker("Execute", selection: $settings.executeSelection)
            phasePicker("Review", selection: $settings.reviewSelection)
        } header: {
            Text("Phase Models")
        } footer: {
            Text(
                "Each phase uses the default model unless you choose one here. For example, keep execute on a local model while review runs on a stronger cloud model."
            )
        }
    }

    private func phasePicker(_ title: String, selection: Binding<ModelSelection?>) -> some View {
        Picker(title, selection: selection) {
            Text("Follow Default").tag(Optional<ModelSelection>.none)
            selectionOptions(
                current: selection.wrappedValue,
                tag: { Optional($0) }
            )
        }
        .pickerStyle(.menu)
    }

    /// Grouped cloud/local options. A tagged option for the current value is
    /// kept even when the catalog no longer lists it (deleted download,
    /// unfetched cloud id) so the picker never renders an empty selection.
    @ViewBuilder
    private func selectionOptions<Tag: Hashable>(
        current: ModelSelection?,
        tag: @escaping (ModelSelection) -> Tag
    ) -> some View {
        let cloudIDs = catalog.allCloudModelIDs
        let localIDs = catalog.installedLocalModelIDs
        let orphanCloud = current.flatMap {
            $0.origin == .cloud && !cloudIDs.contains($0.identifier) ? $0 : nil
        }
        let orphanLocal = current.flatMap {
            $0.origin == .local && !localIDs.contains($0.identifier) ? $0 : nil
        }
        Section("Cloud") {
            if let orphanCloud {
                Label(orphanCloud.displayName, systemImage: SageDesign.Symbol.modelCloud)
                    .tag(tag(orphanCloud))
            }
            ForEach(cloudIDs, id: \.self) { id in
                Label(id, systemImage: SageDesign.Symbol.modelCloud)
                    .tag(tag(.cloud(id)))
            }
            if cloudIDs.isEmpty && orphanCloud == nil {
                Text("No cloud models yet")
            }
        }
        Section("Local") {
            if let orphanLocal {
                Label(orphanLocal.displayName, systemImage: SageDesign.Symbol.modelLocal)
                    .tag(tag(orphanLocal))
            }
            ForEach(localIDs, id: \.self) { id in
                Label(id, systemImage: SageDesign.Symbol.modelLocal)
                    .tag(tag(.local(id)))
            }
            if localIDs.isEmpty && orphanLocal == nil {
                Text("None downloaded")
            }
        }
    }

    // MARK: - Cloud catalog

    private var cloudModelsSection: some View {
        Section {
            LabeledContent("Provider") {
                Text(settings.baseURL)
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .sageHelp("Change the Base URL and API key on the Connection pane")
            }

            ForEach(catalog.allCloudModelIDs, id: \.self) { id in
                cloudModelRow(id)
            }

            LabeledContent("Add Custom Model") {
                HStack(spacing: SageDesign.Spacing.small) {
                    TextField("model-id", text: $customModelDraft)
                        .onSubmit(addCustomModel)
                    Button("Add", action: addCustomModel)
                        .disabled(trimmedCustomDraft.isEmpty)
                }
            }

            Button {
                Task { await catalog.refreshCloudModels() }
            } label: {
                if catalog.isFetchingCloudModels {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…")
                    }
                } else {
                    Label("Refresh from Provider", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(catalog.isFetchingCloudModels)
        } header: {
            Text("Cloud Models")
        } footer: {
            Text(
                "Discovered from the provider’s model list and cached locally. Add an ID manually for models the provider doesn’t list."
            )
        }
    }

    private func cloudModelRow(_ id: String) -> some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Label(id, systemImage: SageDesign.Symbol.modelCloud)
            Spacer()
            if catalog.manualCloudModelIDs.contains(id) {
                Button {
                    catalog.removeManualCloudModel(id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .sageHelp("Remove custom model")
                .accessibilityLabel("Remove \(id)")
            }
        }
    }

    private var trimmedCustomDraft: String {
        customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addCustomModel() {
        let id = trimmedCustomDraft
        guard !id.isEmpty else { return }
        catalog.addManualCloudModel(id)
        customModelDraft = ""
    }

    // MARK: - Local models

    private var localModelsSection: some View {
        Section {
            engineStatusRow

            ForEach(localEntries, id: \.repoID) { entry in
                localModelRow(entry)
            }

            Button {
                browsePresented = true
            } label: {
                Label("Browse Hugging Face…", systemImage: "arrow.down.circle")
            }
            .disabled(!LocalModelEngine.isAvailable)
        } header: {
            Text("Local Models")
        } footer: {
            Text(
                LocalModelEngine.isAvailable
                    ? "Downloaded from Hugging Face (mlx-community builds). They run entirely on this Mac."
                    : "Local models require Apple Silicon (MLX). This Mac can’t run them."
            )
        }
    }

    private struct LocalEntry {
        let repoID: String
        let state: ModelCatalog.LocalModelState
    }

    /// Installed, downloading, and failed models — the states that need a row.
    /// Not-installed models live in the browse sheet, not here.
    private var localEntries: [LocalEntry] {
        catalog.localStates
            .compactMap { repoID, state in
                switch state {
                case .installed, .downloading, .failed:
                    return LocalEntry(repoID: repoID, state: state)
                case .notInstalled:
                    return nil
                }
            }
            .sorted { $0.repoID < $1.repoID }
    }

    private var engineStatusRow: some View {
        LabeledContent("Engine") {
            Group {
                switch LocalEngineObserver.shared.status {
                case .idle:
                    Text("Idle")
                case .loading(let modelID):
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading \(shortName(modelID))…")
                    }
                case .downloading(let modelID, let progress):
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Fetching \(shortName(modelID)) \(Int(progress * 100))%…")
                    }
                case .ready(let modelID):
                    Label(
                        "\(shortName(modelID)) ready",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(SageDesign.Palette.successText)
                case .failed(_, let reason):
                    Label(reason, systemImage: "xmark.circle.fill")
                        .foregroundStyle(SageDesign.Palette.dangerText)
                }
            }
            .sageFont(type.caption)
            .accessibilityElement(children: .combine)
        }
    }

    private func localModelRow(_ entry: LocalEntry) -> some View {
        let name = ModelSelection.local(entry.repoID).displayName
        return HStack(spacing: SageDesign.Spacing.small) {
            Label(name, systemImage: SageDesign.Symbol.modelLocal)

            Spacer()

            switch entry.state {
            case .installed(let diskBytes):
                Text(ByteCountFormatter.string(fromByteCount: diskBytes, countStyle: .file))
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    pendingDeleteRepoID = entry.repoID
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .sageHelp("Delete downloaded weights")
                .accessibilityLabel("Delete \(name)")

            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 120)
                Text("\(Int(progress * 100))%")
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Cancel") {
                    catalog.cancelDownload(repoID: entry.repoID)
                }
                .controlSize(.small)

            case .failed:
                Button("Retry") {
                    catalog.startDownload(repoID: entry.repoID)
                }
                .controlSize(.small)

            case .notInstalled:
                EmptyView()
            }
        }
    }

    private func shortName(_ repoID: String) -> String {
        ModelSelection.local(repoID).displayName
    }
}
