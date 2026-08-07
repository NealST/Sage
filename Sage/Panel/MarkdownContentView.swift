//
//  MarkdownContentView.swift
//  Sage
//

import MarkdownUI
import SwiftUI

/// Polished Markdown renderer for assistant replies (MarkdownUI).
struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        Markdown(markdown)
            .markdownTheme(.sage)
            .markdownCodeSyntaxHighlighter(TreeSitterCodeHighlighter())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Theme {
    /// Calm, system-native look for macOS agent transcripts.
    static let sage = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(13)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(.accentColor)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12)
            BackgroundColor(Color.primary.opacity(0.06))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(18)
                }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                }
                .markdownMargin(top: 10, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(13)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(12)
                    }
                    .padding(12)
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .markdownMargin(top: 6, bottom: 10)
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                    }
                    .padding(.leading, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 6, bottom: 8)
        }
}
