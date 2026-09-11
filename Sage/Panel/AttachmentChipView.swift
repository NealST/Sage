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
    @State private var previewImage: NSImage?
    /// Upward drag toward removal — tracks 1:1, commits by distance or velocity.
    @State private var dragOffsetY: CGFloat = 0
    @ScaledMetric(relativeTo: .caption) private var nameMaxWidth: CGFloat = 140

    private var canDragRemove: Bool {
        showsRemove && onRemove != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: selectOrPreview) {
                HStack(spacing: 6) {
                    thumbnail
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(attachment.displayName)
                        .sageMicro(type.micro, weight: .medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: nameMaxWidth, alignment: .leading)

                    if !attachment.isAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .sageFont(type.icon, weight: .semibold)
                            .foregroundStyle(SageDesign.Palette.warning)
                            .help("File is no longer available")
                            .accessibilityLabel("File missing")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(
                attachment.isAvailable
                    ? "Opens a Quick Look preview"
                    : "The file is no longer available"
            )

            if showsRemove {
                Button("Remove \(attachment.displayName)", systemImage: "xmark") {
                    onRemove?()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .sageFont(type.icon, weight: .bold)
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 18)
                // Hit slop beyond the visual glyph — small targets should not
                // stay small. Stays inside the chip's padding budget.
                .padding(5)
                .contentShape(Rectangle())
                .help("Remove \(attachment.displayName)")
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
        .gesture(dragRemoveGesture)
        .offset(y: dragOffsetY)
        .opacity(removalOpacity)
        .task(id: attachment.path) {
            guard attachment.kind == .image, attachment.isAvailable else {
                previewImage = nil
                return
            }
            let url = attachment.fileURL
            let data = await Task.detached(priority: .utility) {
                AttachmentImageEncoder.thumbnailData(for: url)
            }.value
            previewImage = data.flatMap(NSImage.init(data:))
        }
    }

    /// Flick the chip up to remove it. Only vertical drags claim the gesture —
    /// horizontal movement belongs to the surrounding chip scroll view.
    private var dragRemoveGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard canDragRemove,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                dragOffsetY = min(0, value.translation.height)
            }
            .onEnded { value in
                guard canDragRemove else { return }
                let shouldRemove = dragOffsetY < -32 || value.velocity.height < -600
                if shouldRemove {
                    onRemove?()
                    // Keep the dragged offset while the removal animation takes over.
                } else {
                    withAnimation(
                        SageDesign.Motion.dragSettle(
                            velocity: value.velocity.height,
                            from: dragOffsetY
                        )
                    ) {
                        dragOffsetY = 0
                    }
                }
            }
    }

    private var removalOpacity: Double {
        guard dragOffsetY < 0 else { return 1 }
        return 1 - min(0.8, Double(-dragOffsetY / 80))
    }

    private func selectOrPreview() {
        if let onSelect {
            onSelect()
        } else {
            QuickLookPresenter.shared.preview(url: attachment.fileURL)
        }
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

    @ViewBuilder private var thumbnail: some View {
        if let previewImage {
            Image(nsImage: previewImage)
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
                        onSelect: onSelect.map { handler in
                            { handler(item) }
                        },
                        onRemove: onRemove.map { handler in
                            { handler(item) }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
