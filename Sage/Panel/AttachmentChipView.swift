//
//  AttachmentChipView.swift
//  Sage
//
//  Messages-style attachment token: preview, name, remove.
//

import AppKit
import SwiftUI

struct AttachmentChipView: View {
    let attachment: MessageAttachment
    var showsRemove: Bool = true
    var isSelected: Bool = false
    var onSelect: (() -> Void)?
    var onRemove: (() -> Void)?

    @Environment(\.sageTypography) private var type

    var body: some View {
        HStack(spacing: 6) {
            thumbnail
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(attachment.displayName)
                .font(.system(size: type.micro, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140, alignment: .leading)

            if showsRemove {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(attachment.displayName)")
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, showsRemove ? 2 : 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.12 : 0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(isSelected ? 0.7 : 0),
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if let onSelect {
                onSelect()
            } else {
                QuickLookPresenter.shared.preview(url: attachment.fileURL)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens a Quick Look preview")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let kind: String
        switch attachment.kind {
        case .image: kind = "image"
        case .file: kind = "file"
        case .folder: kind = "folder"
        }
        return "\(attachment.displayName), \(kind)"
    }

    @ViewBuilder
    private var thumbnail: some View {
        if attachment.kind == .image, let image = NSImage(contentsOf: attachment.fileURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.path))
                .resizable()
                .scaledToFit()
        }
    }
}

struct AttachmentChipBar: View {
    let attachments: [MessageAttachment]
    var selectedID: UUID?
    var showsRemove: Bool
    var onSelect: ((MessageAttachment) -> Void)?
    var onRemove: ((MessageAttachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { item in
                    AttachmentChipView(
                        attachment: item,
                        showsRemove: showsRemove,
                        isSelected: item.id == selectedID,
                        onSelect: { onSelect?(item) },
                        onRemove: { onRemove?(item) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
