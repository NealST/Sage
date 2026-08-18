//
//  SettingsFormChrome.swift
//  Sage
//

import SwiftUI

enum SettingsConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

enum SettingsFormChrome {
    @ViewBuilder
    static func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Text(title)
                .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            content()
        }
    }

    static var divider: some View {
        Divider()
            .padding(.leading, 14)
    }

    @ViewBuilder
    static func field<Content: View>(
        title: String,
        error: String?,
        isFirst: Bool = false,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                    .foregroundStyle(.secondary)

                content()
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, 14)
            .padding(.top, isFirst ? 12 : 10)
            .padding(.bottom, isLast ? 12 : 10)

            if let error {
                Text(error)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        }
    }

    static func capabilityRow(
        symbol: String,
        title: String,
        detail: String,
        isFirst: Bool = false,
        isLast: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SageDesign.Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func quickToggleRow(
        title: String,
        detail: String? = nil,
        isLast: Bool = false,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: SageDesign.Spacing.md) {
            Spacer()
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
