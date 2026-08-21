//
//  PathTextSupport.swift
//  Sage
//

import AppKit
import Foundation
import SwiftUI

enum PathTextSupport {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tif", "tiff", "heic", "heif", "bmp", "ico",
    ]

    /// Custom schemes handled by transcript `openURL` for local paths.
    static let revealScheme = "sage-reveal"
    static let quickLookScheme = "sage-ql"

    private static let pathRegex: NSRegularExpression = {
        // ~/… or absolute /Users|/home paths. Avoid matching URL schemes (no "://").
        let pattern = #"(?<![A-Za-z0-9@:])(~(?:/[^ \t\n<>"'`]+)+|/(?:Users|home)/[^ \t\n<>"'`]+)"#
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            preconditionFailure("PathTextSupport path regex is invalid: \(error)")
        }
    }()

    static func isImagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    static func fileURL(
        fromPath path: String,
        policy: PathGuard.Policy = .home
    ) -> URL? {
        if let url = PathGuard.fileURL(forDisplayPath: path, policy: policy) {
            return url
        }
        // Legacy absolute / tilde paths that fall outside the active project root.
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// All existing local file URLs mentioned in `text` (deduped, path order).
    static func allFileURLs(
        in text: String,
        policy: PathGuard.Policy = .home
    ) -> [URL] {
        var urls = rawPathMatches(in: text).compactMap { fileURL(fromPath: $0, policy: policy) }
        // Whole-string project-relative path (e.g. UnifiedDiffView header).
        if urls.isEmpty,
           let only = fileURL(fromPath: text.trimmingCharacters(in: .whitespacesAndNewlines), policy: policy) {
            urls = [only]
        }
        return urls
    }

    static func actionURL(forFileURL fileURL: URL, quickLook: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = quickLook ? quickLookScheme : revealScheme
        components.host = "local"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.path)]
        return components.url
    }

    static func fileURL(fromAction url: URL) -> URL? {
        guard url.scheme == revealScheme || url.scheme == quickLookScheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Builds an AttributedString with tappable local paths (reveal / Quick Look).
    /// Missing files stay visible but muted and non-interactive.
    static func attributedString(
        from text: String,
        policy: PathGuard.Policy = .home
    ) -> AttributedString {
        var attributed = AttributedString(text)
        let nsString = text as NSString
        let full = NSRange(location: 0, length: nsString.length)
        let matches = pathRegex.matches(in: text, options: [], range: full)

        if matches.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let fileURL = fileURL(fromPath: trimmed, policy: policy),
               let link = actionURL(forFileURL: fileURL, quickLook: isImagePath(trimmed)),
               let range = text.range(of: trimmed),
               let attrRange = Range(range, in: attributed) {
                attributed[attrRange].link = link
                attributed[attrRange].foregroundColor = Color.accentColor
                attributed[attrRange].underlineStyle = .single
            }
            return attributed
        }

        for match in matches.reversed() {
            guard match.numberOfRanges >= 1 else { continue }
            var raw = nsString.substring(with: match.range)
            while let last = raw.last, ".,;:)]}".contains(last) {
                raw.removeLast()
            }
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let trimmedEnd = text.index(swiftRange.lowerBound, offsetBy: raw.count)
            guard trimmedEnd <= text.endIndex else { continue }
            let pathRange = swiftRange.lowerBound..<trimmedEnd
            guard let attrRange = Range(pathRange, in: attributed) else { continue }

            if let fileURL = fileURL(fromPath: raw, policy: policy),
               let link = actionURL(forFileURL: fileURL, quickLook: isImagePath(raw)) {
                attributed[attrRange].link = link
                attributed[attrRange].foregroundColor = Color.accentColor
                attributed[attrRange].underlineStyle = .single
            } else {
                // Path-shaped but missing — keep readable, signal it's inactive.
                attributed[attrRange].foregroundColor = Color.secondary
            }
        }

        return attributed
    }

    @discardableResult
    static func handleActionURL(_ url: URL) -> OpenURLAction.Result {
        switch url.scheme {
        case revealScheme:
            guard let fileURL = fileURL(fromAction: url) else { return .discarded }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return .handled

        case quickLookScheme:
            guard let fileURL = fileURL(fromAction: url) else { return .discarded }
            // ⌘-click reveals in Finder (macOS familiarity); plain click = Quick Look.
            if NSEvent.modifierFlags.contains(.command) {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } else {
                QuickLookPresenter.shared.preview(url: fileURL)
            }
            return .handled

        case "http", "https", "mailto":
            return .systemAction

        default:
            return .discarded
        }
    }

    static var openURLAction: OpenURLAction {
        OpenURLAction { url in
            handleActionURL(url)
        }
    }

    // MARK: - Private

    private static func rawPathMatches(in text: String) -> [String] {
        let nsString = text as NSString
        let full = NSRange(location: 0, length: nsString.length)
        return pathRegex.matches(in: text, options: [], range: full).compactMap { match in
            var raw = nsString.substring(with: match.range)
            while let last = raw.last, ".,;:)]}".contains(last) {
                raw.removeLast()
            }
            return raw.isEmpty ? nil : raw
        }
    }
}
