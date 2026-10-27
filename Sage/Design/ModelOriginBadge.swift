//
//  ModelOriginBadge.swift
//  Sage
//
//  Supply-source tag distinguishing local (on-device) from cloud models.
//  Same shape as the working badge so chips across the app read as one family.
//

import SwiftUI

struct ModelOriginBadge: View {
    let origin: ModelOrigin
    @Environment(\.sageTypography) private var type

    var body: some View {
        Label(title, systemImage: icon)
            .sageMicro(type.micro, weight: .medium)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
            .padding(.vertical, SageDesign.Spacing.compactChipVertical)
            .sageGlassChip()
            .accessibilityLabel(isLocal ? "Local model" : "Cloud model")
    }

    private var isLocal: Bool { origin == .local }

    private var title: String { isLocal ? "Local" : "Cloud" }

    private var icon: String {
        isLocal ? SageDesign.Symbol.modelLocal : SageDesign.Symbol.modelCloud
    }
}
