//
//  WorkspaceChangeSet+Review.swift
//  Sage
//

import Foundation

extension WorkspaceChangeSet {
    func reviewBrief(maxChars: Int) -> String {
        var lines: [String] = []
        if files.isEmpty {
            lines.append("No workspace files changed.")
        } else {
            for file in files {
                lines.append(contentsOf: file.reviewLines())
                lines.append("")
            }
        }
        if opaqueMutationCount > 0 {
            let noun = opaqueMutationCount == 1 ? "write" : "writes"
            lines.append(
                "Note: \(opaqueMutationCount) other \(noun) (shell or similar) aren’t listed."
            )
        }
        return clip(lines.joined(separator: "\n"), maxChars: maxChars)
    }

    private func clip(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars)) + "\n…"
    }
}

extension WorkspaceFileChange {
    fileprivate func reviewLines() -> [String] {
        var lines = ["\(path) (\(kind.reviewLabel))"]
        if let previousPath {
            lines.append("moved from \(previousPath)")
        }
        if hasLineDiff {
            lines.append(stats.summary)
            lines.append(contentsOf: previewLines())
        }
        return lines
    }

    private func previewLines() -> [String] {
        let prior = kind == .added ? "" : (before ?? "")
        let next = after ?? ""
        let operations = LineDiff.withCollapsedContext(
            LineDiff.diff(before: prior, after: next),
            context: 2
        )
        return operations.prefix(80).map { operation in
            switch operation {
            case let .equal(line):
                return " \(line)"

            case let .insert(line):
                return "+\(line)"

            case let .delete(line):
                return "-\(line)"
            }
        }
    }
}

extension WorkspaceChangeKind {
    var reviewLabel: String {
        switch self {
        case .added: return "added"
        case .modified: return "modified"
        case .removed: return "removed"
        case .moved: return "moved"
        case .copied: return "copied"
        case .directory: return "directory"
        }
    }

    var rowLabel: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .removed: return "Removed"
        case .moved: return "Moved"
        case .copied: return "Copied"
        case .directory: return "Folder"
        }
    }

    var symbolName: String {
        switch self {
        case .added: return "doc.badge.plus"
        case .modified: return "doc.text"
        case .removed: return "trash"
        case .moved: return "arrow.right"
        case .copied: return "doc.on.doc"
        case .directory: return "folder.badge.plus"
        }
    }
}
