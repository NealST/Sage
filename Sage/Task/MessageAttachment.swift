//
//  MessageAttachment.swift
//  Sage
//
//  A file the user pinned on a turn. Referenced in place unless Sage
//  created a copy (clipboard images).
//

import Foundation

nonisolated struct MessageAttachment: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case image
        case file
        case folder
    }

    static let maxCount = 8

    let id: UUID
    var kind: Kind
    var displayName: String
    /// Absolute, standardized path.
    var path: String
    /// True when Sage wrote a copy (pasteboard images).
    var isEphemeralCopy: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        displayName: String,
        path: String,
        isEphemeralCopy: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.path = path
        self.isEphemeralCopy = isEphemeralCopy
    }

    var fileURL: URL {
        URL(fileURLWithPath: path)
    }

    var promptLine: String {
        let safePath = Self.sanitizePromptText(displayPath)
        switch kind {
        case .image:
            return "- \"\(safePath)\" (image)"
        case .file:
            return "- \"\(safePath)\" (file)"
        case .folder:
            return "- \"\(safePath)\" (folder)"
        }
    }

    var historicalPromptLine: String {
        switch kind {
        case .image:
            return "- [image: \(Self.sanitizePromptText(displayName))]"
        case .file, .folder:
            return promptLine
        }
    }

    var displayPath: String {
        PathGuard.displayPath(path, policy: .home)
    }

    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue || FileManager.default.isReadableFile(atPath: path)
    }

    /// Exact file or folder path for `PathGuard.readAllowlist`.
    var readAllowlistPath: String {
        fileURL.resolvingSymlinksInPath().path
    }

    nonisolated static func promptListing(
        _ attachments: [Self],
        includeImagePixels: Bool
    ) -> String {
        guard !attachments.isEmpty else { return "" }
        let lines = attachments.map { item in
            includeImagePixels ? item.promptLine : item.historicalPromptLine
        }
        return (["Attached:"] + lines).joined(separator: "\n")
    }

    nonisolated static func submitQuery(text: String, attachments: [Self]) -> String {
        if !text.isEmpty { return text }
        let names = attachments.map { sanitizePromptText($0.displayName) }
        guard !names.isEmpty else { return "" }
        if names.count == 1 { return "Attached \(names[0])" }
        return "Attached \(names.joined(separator: ", "))"
    }

    nonisolated static func readAllowlist(
        from events: [AgentEvent],
        recentUserTurnLimit: Int = 8
    ) -> [String] {
        let recentUserEvents = events
            .filter { $0.kind == .userInput && !$0.attachments.isEmpty }
            .suffix(max(recentUserTurnLimit, 1))
        return Array(
            Set(recentUserEvents.flatMap(\.attachments).filter(\.isAvailable).map(\.readAllowlistPath))
        )
            .sorted()
    }

    nonisolated static func deleteManagedCopies(_ attachments: [Self]) {
        for attachment in attachments where attachment.isEphemeralCopy {
            try? FileManager.default.removeItem(at: attachment.fileURL)
        }
    }

    nonisolated static func deleteAllManagedCopies() {
        let directory = AppSupportPaths.attachmentsInbox(createIfNeeded: false)
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated static func sanitizePromptText(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }
        .joined()
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated static func kind(for url: URL) -> Kind {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue { return .folder }
        let ext = url.pathExtension.lowercased()
        if [
            "png", "jpg", "jpeg", "gif", "webp", "tif", "tiff", "heic", "heif", "bmp", "ico",
        ].contains(ext) {
            return .image
        }
        return .file
    }
}

extension AgentEvent {
    nonisolated func modelFacingContent(includeImagePixels: Bool) -> String {
        let listing = MessageAttachment.promptListing(
            attachments,
            includeImagePixels: includeImagePixels
        )
        guard !listing.isEmpty else { return content }
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return listing }
        return content + "\n\n" + listing
    }

    nonisolated func embeddingAttachmentListing(includeImagePixels: Bool) -> AgentEvent {
        guard !attachments.isEmpty else { return self }
        var copy = self
        copy.content = modelFacingContent(includeImagePixels: includeImagePixels)
        return copy
    }
}
