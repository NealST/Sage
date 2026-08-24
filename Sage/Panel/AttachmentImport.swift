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
    static let tooManyHint = "8 files at a time."
    static let outsideHomeHint = "Sage can only use files in your home folder."
    static let unreadableHint = "That file couldn’t be added."

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
    ) -> AttachmentImportOutcome? {
        switch pasteboardKind(pasteboard) {
        case .files(let urls):
            return resolve(urls, into: existing)

        case .image:
            guard let attachment = persistPasteboardImage(pasteboard) else {
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
        case image
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
        if hasImage && text.isEmpty { return .image }
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
        var hint: String?
        for result in incoming {
            if next.count >= MessageAttachment.maxCount {
                hint = tooManyHint
                break
            }
            switch result {
            case .success(let attachment):
                guard seen.insert(attachment.path).inserted else { continue }
                next.append(attachment)

            case .failure(let error):
                hint = error.hint
            }
        }
        return AttachmentImportOutcome(attachments: next, hint: hint)
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

    @MainActor
    private static func persistPasteboardImage(_ pasteboard: NSPasteboard) -> MessageAttachment? {
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }
        return persistImage(image)
    }

    @MainActor
    private static func persistImage(_ image: NSImage) -> MessageAttachment? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
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
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let image = NSImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                Task { @MainActor in
                    continuation.resume(returning: persistImage(image))
                }
            }
        }
    }
}
