//
//  AgentComposerView+ModelPicker.swift
//  Sage
//
//  The composer's supply-source switch. Picking here changes the global
//  default model; phases that carry their own selection are called out in
//  the menu footer so an override is never a silent surprise.
//

import SwiftUI

/// Pull-down picker that replaces the status row's plain model text. Cloud
/// and local candidates are grouped (HIG menus: organization over one flat
/// list); the current default carries the checkmark; in-flight downloads
/// stay visible but dimmed.
struct ComposerModelPicker: View {
    /// Cloud lists can run long — the full catalog lives in Settings.
    private static let inlineCloudLimit = 15

    @Environment(AppState.self) private var appState
    @Environment(\.sageTypography) private var type

    private var settings: ModelSettings { appState.settings }

    private var catalog: ModelCatalog { .shared }

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: SageDesign.Spacing.extraSmall) {
                Text(settings.defaultSelection.displayName)
                    .sageMicro(type.micro, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ModelOriginBadge(origin: settings.defaultSelection.origin)
            }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .sageHelp("Switch model")
        .accessibilityLabel(accessibilityText)
        .onAppear {
            // Fallback refresh: the menu shows cached IDs immediately, and a
            // composer open nudges the catalog back in sync with the provider.
            Task { await catalog.refreshCloudModels() }
        }
    }

    private var accessibilityText: String {
        let origin = settings.defaultSelection.origin == .local ? "local" : "cloud"
        return "Model \(settings.defaultSelection.displayName), \(origin)"
    }

    // MARK: - Menu

    @ViewBuilder private var menuContent: some View {
        cloudSection
        localSection
        Divider()
        if settings.hasRoleOverrides {
            Text("Some phases use their own model")
        }
        Button {
            NotificationCenter.default.post(name: .sageOpenSettingsModels, object: nil)
        } label: {
            Label("Manage Models…", systemImage: SageDesign.Symbol.modelManage)
        }
    }

    @ViewBuilder private var cloudSection: some View {
        let ids = catalog.allCloudModelIDs
        Section("Cloud") {
            if ids.isEmpty {
                Text("No cloud models yet")
            } else {
                ForEach(ids.prefix(Self.inlineCloudLimit), id: \.self) { id in
                    selectButton(.cloud(id))
                }
                if ids.count > Self.inlineCloudLimit {
                    Button {
                        NotificationCenter.default.post(
                            name: .sageOpenSettingsModels,
                            object: nil
                        )
                    } label: {
                        Label("View all in Settings…", systemImage: "ellipsis")
                    }
                }
            }
        }
    }

    @ViewBuilder private var localSection: some View {
        let installed = catalog.installedLocalModelIDs
        let downloading = downloadingLocalIDs
        Section("Local") {
            if installed.isEmpty && downloading.isEmpty {
                Text("None downloaded")
            } else {
                ForEach(installed, id: \.self) { repoID in
                    selectButton(.local(repoID))
                }
                ForEach(downloading, id: \.self) { repoID in
                    // HIG menus: dim unavailable items rather than hiding them.
                    Label(
                        "\(ModelSelection.local(repoID).displayName) · downloading",
                        systemImage: "arrow.down.circle"
                    )
                }
            }
        }
    }

    private var downloadingLocalIDs: [String] {
        catalog.localStates
            .filter { state in
                if case .downloading = state.value { return true }
                return false
            }
            .map(\.key)
            .sorted()
    }

    @ViewBuilder
    private func selectButton(_ selection: ModelSelection) -> some View {
        Button {
            select(selection)
        } label: {
            if settings.defaultSelection == selection {
                // branchMenu convention: the current item trades its origin
                // glyph for the checkmark — one mark per item.
                Label(selection.displayName, systemImage: "checkmark")
            } else {
                Label(
                    selection.displayName,
                    systemImage: selection.origin == .local
                        ? SageDesign.Symbol.modelLocal
                        : SageDesign.Symbol.modelCloud
                )
            }
        }
    }

    private func select(_ selection: ModelSelection) {
        settings.defaultSelection = selection
        selection.warmUpLocalEngineIfApplicable()
    }
}
