//
//  AttachmentChipView.swift
//  Sage
//
//  Messages-style attachment token: preview, name, remove.
//

import AppKit
import QuickLookThumbnailing
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
    /// Fires the threshold haptic once per gesture, crossing back and forth
    /// inside a single drag stays quiet.
    @State private var didFireRemovalHaptic = false
    /// Commit in flight: the chip is mid throw-out and no longer interactive.
    @State private var isThrownOut = false
    @State private var hoveringRemove = false
    @ScaledMetric(relativeTo: .caption) private var nameMaxWidth: CGFloat = 140

    private var canDragRemove: Bool {
        showsRemove && onRemove != nil
    }

    @ViewBuilder
    var body: some View {
        if canDragRemove {
            interactiveChip
        } else if attachment.isAvailable {
            // Transcript chips double as drag sources (drag out to copy the
            // file). Composer variants keep the flick-to-remove gesture,
            // which owns the pointer — the two drags never share a chip.
            interactiveChip
                .draggable(attachment.fileURL)
        } else {
            interactiveChip
        }
    }

    private var interactiveChip: some View {
        HStack(spacing: SageDesign.Spacing.extraSmall) {
            Button(action: selectOrPreview) {
                HStack(spacing: SageDesign.Spacing.labelGap) {
                    thumbnail
                        .frame(width: SageDesign.Control.iconButton, height: SageDesign.Control.iconButton)
                        .clipShape(
                            RoundedRectangle(cornerRadius: SageDesign.Glass.mini, style: .continuous)
                        )

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
                removeButton
            }
        }
        // Tighter than the chip tokens on purpose: the 22pt hit area inside a
        // small capsule leaves little room, and these chips sit in a dense
        // wrapping row where full chip padding would balloon the composer.
        .padding(.leading, 5)
        .padding(.trailing, showsRemove ? 2 : SageDesign.Spacing.compactChipHorizontal)
        .padding(.vertical, SageDesign.Spacing.compactChipVertical)
        .background(
            RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                .fill(
                    Color.primary.opacity(
                        isSelected
                            ? SageDesign.Chrome.selectionFillOpacity
                            : SageDesign.Chrome.pillFillOpacity
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(isSelected ? SageDesign.Chrome.accentRingOpacity : 0),
                    lineWidth: 1
                )
        }
        .gesture(dragRemoveGesture)
        .offset(y: dragOffsetY)
        .opacity(removalOpacity)
        .task(id: attachment.path) {
            guard attachment.isAvailable else {
                previewImage = nil
                return
            }
            switch attachment.kind {
            case .image:
                let url = attachment.fileURL
                let data = await Task.detached(priority: .utility) {
                    AttachmentImageEncoder.thumbnailData(for: url)
                }.value
                previewImage = data.flatMap(NSImage.init(data:))

            case .file:
                // A real document preview beats the generic icon — the same
                // Quick Look system the chip's click opens into.
                previewImage = await Self.quickLookThumbnail(for: attachment.fileURL)

            case .folder:
                // Folders keep the system folder icon (the fallback below).
                previewImage = nil
            }
        }
    }

    /// Remove glyph affordance — the chip itself only hints at removal on drag.
    private var removeButton: some View {
        Button("Remove \(attachment.displayName)", systemImage: "xmark") {
            onRemove?()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .sageFont(type.icon, weight: .bold)
        .foregroundStyle(
            hoveringRemove ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
        )
        .frame(width: SageDesign.Control.iconButton, height: SageDesign.Control.iconButton)
        // Hit slop beyond the visual glyph — small targets should not
        // stay small. Stays inside the chip's padding budget.
        .sageHitSlop(visualSize: SageDesign.Control.iconButton)
        .onHover { hoveringRemove = $0 }
        .help("Remove \(attachment.displayName)")
    }

    /// Quick Look thumbnail at the chip's display size (2x for crispness).
    /// Returns nil on failure so the caller falls back to the workspace icon.
    private static func quickLookThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 22, height: 22),
            scale: 2,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(
                    returning: representation.map { NSImage(cgImage: $0.cgImage, size: request.size) }
                )
            }
        }
    }

    /// Flick the chip up to remove it. Only vertical drags claim the gesture —
    /// horizontal movement belongs to the surrounding chip scroll view.
    private var dragRemoveGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard canDragRemove, !isThrownOut,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                let offset = min(0, value.translation.height)
                // Crossing the commit distance while still dragging — the
                // gesture snaps "armed", and the trackpad clicks along.
                if offset < -Self.removalThreshold, !didFireRemovalHaptic {
                    didFireRemovalHaptic = true
                    NSHapticFeedbackManager.defaultPerformer.perform(
                        .alignment,
                        performanceTime: .now
                    )
                }
                dragOffsetY = offset
            }
            .onEnded { value in
                guard canDragRemove, !isThrownOut else { return }
                didFireRemovalHaptic = false
                let shouldRemove = dragOffsetY < -Self.removalThreshold
                    || value.velocity.height < -SageDesign.Motion.DragThrow.flickVelocity
                if shouldRemove {
                    removeWithThrow(velocity: value.velocity.height)
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

    /// Distance past which an upward flick commits the removal.
    private static let removalThreshold: CGFloat = 32

    /// The commit continues the throw at the release velocity — the chip
    /// leaves at the finger's speed while fading, instead of stopping dead
    /// to fade in place (the spring-back path already carries velocity; the
    /// commit must not be the one place momentum dies). The actual removal
    /// lands a beat later, once the chip is already invisible.
    private func removeWithThrow(velocity: CGFloat) {
        guard let settle = SageDesign.Motion.dragSettle(
            velocity: velocity,
            from: dragOffsetY,
            to: dragOffsetY - SageDesign.Motion.DragThrow.distance
        ) else {
            // Reduce Motion: no throw — remove immediately, as before.
            onRemove?()
            return
        }
        withAnimation(settle) {
            isThrownOut = true
            dragOffsetY -= SageDesign.Motion.DragThrow.distance
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(SageDesign.Motion.DragThrow.removalDelay * 1000)))
            onRemove?()
        }
    }

    private var removalOpacity: Double {
        if isThrownOut { return 0 }
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
            HStack(spacing: SageDesign.Spacing.extraSmall) {
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
