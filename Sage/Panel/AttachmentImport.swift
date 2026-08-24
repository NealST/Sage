//
//  AttachmentImport.swift
//  Sage
//
//  Drop / paste / open-panel → MessageAttachment. Rejects paths outside ~.
//

import AppKit
import UniformTypeIdentifiers

nonisolated struct AttachmentImportOutcome: Sendable, Equatable {
    var attachments: [MessageAttachment]
    var hint: String?
}

enum AttachmentImport {
    nonisolated static let tooManyHint = "8 files at a time."
    nonisolated static let outsideHomeHint = "Sage can only use files in your home folder."
    nonisolated static let unreadableHint = "That file couldn’t be added."
    nonisolated static let duplicateHint = "That item is already attached."

    /// Files and folders already on disk. Copies nothing.
    nonisolated static func resolve(
        _ urls: [URL],
        into existing: [MessageAttachment]
    ) -> AttachmentImportOutcome {
        merge(candidates(from: urls), into: existing)
    }

    @MainActor
    static func fromPasteboard(
        _ pasteboard: NSPasteboard = .general,
        into existing: [MessageAttachment]
    ) async -> AttachmentImportOutcome? {
        switch pasteboardKind(pasteboard) {
        case .files(let urls):
            return resolve(urls, into: existing)

        case .image(let data):
            guard let attachment = await Task.detached(priority: .userInitiated, operation: {
                persistImageData(data)
            }).value else {
                return AttachmentImportOutcome(attachments: existing, hint: unreadableHint)
            }
            return merge([.success(attachment)], into: existing)

        case .text:
            return nil
        }
    }

    @MainActor
    static func pickFromOpenPanel(
        policy: PathGuard.Policy,
        into existing: [MessageAttachment]
    ) -> AttachmentImportOutcome? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Choose files to add to this message"
        panel.directoryURL = policy.defaultWorkingDirectory
        guard panel.runModal() == .OK else { return nil }
        return resolve(panel.urls, into: existing)
    }

    @MainActor
    static func fromItemProviders(
        _ providers: [NSItemProvider],
        into existing: [MessageAttachment]
    ) async -> AttachmentImportOutcome {
        var urls: [URL] = []
        var imageAttachments: [MessageAttachment] = []
        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                urls.append(url)
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let attachment = await persistProviderImage(provider) {
                imageAttachments.append(attachment)
            }
        }
        let fromDisk = candidates(from: urls)
        let fromImages = imageAttachments.map { Result<MessageAttachment, ImportError>.success($0) }
        return merge(fromDisk + fromImages, into: existing)
    }

    @MainActor
    static func pasteboardHasNonTextPayload(_ pasteboard: NSPasteboard = .general) -> Bool {
        if case .text = pasteboardKind(pasteboard) { return false }
        return true
    }

    // MARK: - Internals

    private enum PasteboardKind {
        case files([URL])
        case image(Data)
        case text
    }

    @MainActor
    private static func pasteboardKind(_ pasteboard: NSPasteboard) -> PasteboardKind {
        let urls = fileURLs(from: pasteboard)
        if !urls.isEmpty { return .files(urls) }
        let hasImage = pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
            || pasteboard.types?.contains(.tiff) == true
            || pasteboard.types?.contains(.png) == true
        let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let types = pasteboard.types ?? []
        let imageIndex = types.firstIndex { type in
            type == .tiff || type == .png
                || UTType(type.rawValue)?.conforms(to: .image) == true
        }
        let textIndex = types.firstIndex(of: .string)
        let imageIsPrimary = imageIndex.map { $0 < (textIndex ?? .max) } ?? false
        if hasImage && (text.isEmpty || imageIsPrimary) {
            if let data = pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: .tiff)
                ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation {
                return .image(data)
            }
        }
        return .text
    }

    @MainActor
    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            return urls
        }
        return (pasteboard.propertyList(forType: .fileURL) as? [String] ?? []).compactMap(URL.init(string:))
    }

    nonisolated static func candidates(from urls: [URL]) -> [Result<MessageAttachment, ImportError>] {
        urls.map { url in
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
            else {
                return .failure(.unreadable)
            }
            guard isDirectory.boolValue || FileManager.default.isReadableFile(atPath: resolved.path)
            else {
                return .failure(.unreadable)
            }
            guard PathGuard.isInsideHome(resolved.path) else {
                return .failure(.outsideHome)
            }
            return .success(
                MessageAttachment(
                    kind: MessageAttachment.kind(for: resolved),
                    displayName: resolved.lastPathComponent,
                    path: resolved.path
                )
            )
        }
    }

    nonisolated static func merge(
        _ incoming: [Result<MessageAttachment, ImportError>],
        into existing: [MessageAttachment]
    ) -> AttachmentImportOutcome {
        var next = existing
        var seen = Set(existing.map(\.path))
        var outsideHomeCount = 0
        var unreadableCount = 0
        var duplicateCount = 0
        var overflowCount = 0
        for result in incoming {
            switch result {
            case .success(var attachment):
                guard seen.insert(attachment.path).inserted else {
                    duplicateCount += 1
                    MessageAttachment.deleteManagedCopies([attachment])
                    continue
                }
                guard next.count < MessageAttachment.maxCount else {
                    overflowCount += 1
                    MessageAttachment.deleteManagedCopies([attachment])
                    continue
                }
                if attachment.isEphemeralCopy, attachment.kind == .image {
                    attachment.displayName = nextManagedImageName(in: next)
                }
                next.append(attachment)

            case .failure(let error):
                switch error {
                case .outsideHome: outsideHomeCount += 1
                case .unreadable: unreadableCount += 1
                }
            }
        }
        let hint = importHint(
            overflow: overflowCount,
            outsideHome: outsideHomeCount,
            unreadable: unreadableCount,
            duplicates: duplicateCount
        )
        return AttachmentImportOutcome(attachments: next, hint: hint)
    }

    nonisolated private static func nextManagedImageName(
        in attachments: [MessageAttachment]
    ) -> String {
        let names = Set(attachments.map(\.displayName))
        var index = 1
        while names.contains("Image \(index).png") { index += 1 }
        return "Image \(index).png"
    }

    nonisolated private static func importHint(
        overflow: Int,
        outsideHome: Int,
        unreadable: Int,
        duplicates: Int
    ) -> String? {
        if overflow > 0, outsideHome == 0, unreadable == 0, duplicates == 0 {
            return tooManyHint
        }
        if outsideHome > 0, overflow == 0, unreadable == 0, duplicates == 0 {
            return outsideHomeHint
        }
        if unreadable > 0, overflow == 0, outsideHome == 0, duplicates == 0 {
            return unreadableHint
        }
        if duplicates > 0, overflow == 0, outsideHome == 0, unreadable == 0 {
            return duplicateHint
        }
        var reasons: [String] = []
        if overflow > 0 { reasons.append("\(overflow) over the 8-file limit") }
        if outsideHome > 0 { reasons.append("\(outsideHome) outside your home folder") }
        if unreadable > 0 { reasons.append("\(unreadable) unreadable") }
        if duplicates > 0 { reasons.append("\(duplicates) already attached") }
        guard !reasons.isEmpty else { return nil }
        return "Skipped " + reasons.joined(separator: ", ") + "."
    }

    enum ImportError: Error, Sendable {
        case outsideHome
        case unreadable

        var hint: String {
            switch self {
            case .outsideHome: return AttachmentImport.outsideHomeHint
            case .unreadable: return AttachmentImport.unreadableHint
            }
        }
    }

    nonisolated private static func persistImageData(_ data: Data) -> MessageAttachment? {
        guard let png = AttachmentImageEncoder.pngData(from: data) else { return nil }
        let directory = AppSupportPaths.attachmentsInbox(createIfNeeded: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return MessageAttachment(
            kind: .image,
            displayName: "Image.png",
            path: url.standardizedFileURL.path,
            isEphemeralCopy: true
        )
    }

    @MainActor
    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @MainActor
    private static func persistProviderImage(_ provider: NSItemProvider) async -> MessageAttachment? {
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            persistImageData(data)
        }.value
    }
}
