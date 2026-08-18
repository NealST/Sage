//
//  SageMarkdownTheme.swift
//  Sage
//

import AppKit
import MarkdownUI
import SwiftUI

extension Theme {
    /// GitHub-flavored structure with Apple system colors and airy reading rhythm.
    ///
    /// Layout mirrors `Theme.gitHub` / github-markdown-css (heading rules, tables,
    /// blockquotes, task lists) but uses semantic AppKit colors so light/dark and
    /// accessibility contrast follow the system — no Primer hex tokens.
    /// Deliberately omits a page `BackgroundColor` so the panel material shows through.
    static let sage = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .strong {
            FontWeight(.semibold)
        }
        .strikethrough {
            StrikethroughStyle(.single)
            ForegroundColor(.secondary)
        }
        .link {
            ForegroundColor(.accentColor)
            UnderlineStyle(.single)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(Color(nsColor: .quaternarySystemFill))
        }
        // Modest top margins so a leading heading isn’t airy-empty (CSS first-child
        // collapse). Breathing between blocks comes mostly from previous bottom margins.
        .heading1 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.35))
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 8, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.65))
                    }
                Divider().overlay(Color(nsColor: .separatorColor))
            }
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 10, bottom: 14)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.35))
                    }
                Divider().overlay(Color(nsColor: .separatorColor))
            }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 10, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.15))
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 8, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.0))
                }
        }
        .heading5 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 8, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.92))
                    ForegroundColor(.secondary)
                }
        }
        .heading6 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 8, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.88))
                    ForegroundColor(.secondary)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.38))
                .markdownMargin(top: 0, bottom: 16)
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 8, bottom: 16)
        }
        .codeBlock { configuration in
            SageCodeBlockView(configuration: configuration)
                .markdownMargin(top: 8, bottom: 16)
        }
        .image { configuration in
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .markdownMargin(top: 10, bottom: 16)
        }
        .list { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 16)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.28), bottom: .em(0.12))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    configuration.isCompleted ? Color.secondary.opacity(0.7) : Color.secondary,
                    Color(nsColor: .quaternarySystemFill)
                )
                .imageScale(.small)
                .relativeFrame(minWidth: .em(1.6), alignment: .trailing)
        }
        .table { configuration in
            ScrollView(.horizontal, showsIndicators: true) {
                configuration.label
                    .fixedSize(horizontal: true, vertical: true)
                    .markdownTableBorderStyle(.init(color: Color(nsColor: .separatorColor)))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(
                            Color.clear,
                            Color(nsColor: .quaternarySystemFill)
                        )
                    )
            }
            .markdownMargin(top: 4, bottom: 16)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .relativeLineSpacing(.em(0.3))
        }
        .thematicBreak {
            Divider()
                .overlay(Color(nsColor: .separatorColor))
                .padding(.vertical, 8)
                .markdownMargin(top: 20, bottom: 20)
        }
}
