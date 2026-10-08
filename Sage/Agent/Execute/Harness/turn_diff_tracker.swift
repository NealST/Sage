//
//  turn_diff_tracker.swift
//  CodexCore
//
//  Port of codex-rs/core/src/turn_diff_tracker.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Net text diff for the current turn from committed apply_patch
//  mutations, without rereading the workspace. `runTurn` owns the
//  instance and emits `EventMsg.turnDiff` after the sample completes.
//

import ApplyPatch
import CryptoKit
import Foundation

private let zeroOID = String(repeating: "0", count: 40)
private let devNull = "/dev/null"
private let regularFileMode = "100644"

/// rust `TurnDiffTracker`. Shared for the turn; `runTurn` activates it.
public final class TurnDiffTracker: @unchecked Sendable {
    private struct TrackedContent {
        var content: String
        var revision: UInt64
    }

    private struct TrackedPath: Hashable {
        var environmentId: String
        var path: String
    }

    private struct DiffCacheKey: Hashable {
        var leftPath: TrackedPath
        var leftRevision: UInt64?
        var rightPath: TrackedPath
        var rightRevision: UInt64?
    }

    private let lock = NSLock()
    private var valid = true
    private var displayRootsByEnvironment: [String: String] = [:]
    private var baselineByPath: [TrackedPath: TrackedContent] = [:]
    private var currentByPath: [TrackedPath: TrackedContent] = [:]
    private var originByCurrentPath: [TrackedPath: TrackedPath] = [:]
    private var nextRevision: UInt64 = 0
    private var renderedDiffs: [DiffCacheKey: String?] = [:]
    private var unifiedDiff: String?

    /// The tracker `runTurn` / apply_patch record into.
    private static let activeLock = NSLock()
    private static weak var activeInstance: TurnDiffTracker?

    public static var active: TurnDiffTracker? {
        activeLock.lock()
        defer { activeLock.unlock() }
        return activeInstance
    }

    public static func activate(_ tracker: TurnDiffTracker) {
        activeLock.lock()
        activeInstance = tracker
        activeLock.unlock()
    }

    public static func deactivate(_ tracker: TurnDiffTracker) {
        activeLock.lock()
        if activeInstance === tracker {
            activeInstance = nil
        }
        activeLock.unlock()
    }

    public init() {}

    public static func withEnvironmentDisplayRoots(
        _ displayRoots: [(String, String)]
    ) -> TurnDiffTracker {
        let tracker = TurnDiffTracker()
        tracker.reset(displayRoots: displayRoots)
        return tracker
    }

    public func reset(displayRoots: [(String, String)] = []) {
        lock.lock()
        valid = true
        displayRootsByEnvironment = Dictionary(uniqueKeysWithValues: displayRoots)
        baselineByPath = [:]
        currentByPath = [:]
        originByCurrentPath = [:]
        nextRevision = 0
        renderedDiffs = [:]
        unifiedDiff = nil
        lock.unlock()
    }

    public func trackDelta(_ environmentId: String = "", _ delta: AppliedPatchDelta) {
        lock.lock()
        defer { lock.unlock() }
        guard valid else { return }
        if !delta.exact {
            invalidateLocked()
            return
        }
        for change in delta.changes {
            applyChange(environmentId: environmentId, change: change)
        }
        refreshUnifiedDiff()
    }

    public func invalidate() {
        lock.lock()
        invalidateLocked()
        lock.unlock()
    }

    public func getUnifiedDiff() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return unifiedDiff
    }

    public func hasUnifiedDiff() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return unifiedDiff != nil
    }

    private func invalidateLocked() {
        valid = false
        renderedDiffs = [:]
        unifiedDiff = nil
    }

    private func applyChange(environmentId: String, change: AppliedPatchChange) {
        let source = TrackedPath(environmentId: environmentId, path: change.path.standardizedFileURL.path)
        switch change.kind {
        case .add(let content, let overwritten):
            applyAdd(source, content: content, overwritten: overwritten)
        case .delete(let content):
            applyDelete(source, content: content)
        case .update(let movePath, let oldContent, let overwrittenMove, let newContent):
            let dest = movePath.map {
                TrackedPath(environmentId: environmentId, path: $0.standardizedFileURL.path)
            }
            applyUpdate(
                source,
                movePath: dest,
                oldContent: oldContent,
                overwrittenMove: overwrittenMove,
                newContent: newContent
            )
        }
    }

    private func applyAdd(_ path: TrackedPath, content: String, overwritten: String?) {
        originByCurrentPath.removeValue(forKey: path)
        if currentByPath[path] == nil, baselineByPath[path] == nil, let overwritten {
            baselineByPath[path] = trackedContent(overwritten)
        }
        currentByPath[path] = trackedContent(content)
    }

    private func applyDelete(_ path: TrackedPath, content: String) {
        if currentByPath.removeValue(forKey: path) == nil, baselineByPath[path] == nil {
            baselineByPath[path] = trackedContent(content)
        }
        originByCurrentPath.removeValue(forKey: path)
    }

    private func applyUpdate(
        _ sourcePath: TrackedPath,
        movePath: TrackedPath?,
        oldContent: String,
        overwrittenMove: String?,
        newContent: String
    ) {
        if currentByPath[sourcePath] == nil, baselineByPath[sourcePath] == nil {
            baselineByPath[sourcePath] = trackedContent(oldContent)
        }
        guard let destPath = movePath else {
            currentByPath[sourcePath] = trackedContent(newContent)
            return
        }
        if currentByPath[destPath] == nil, baselineByPath[destPath] == nil, let overwrittenMove {
            baselineByPath[destPath] = trackedContent(overwrittenMove)
        }
        let origin = originByCurrentPath.removeValue(forKey: sourcePath) ?? sourcePath
        currentByPath.removeValue(forKey: sourcePath)
        currentByPath[destPath] = trackedContent(newContent)
        originByCurrentPath.removeValue(forKey: destPath)
        if destPath != origin {
            originByCurrentPath[destPath] = origin
        }
    }

    private func trackedContent(_ content: String) -> TrackedContent {
        let revision = nextRevision
        nextRevision += 1
        return TrackedContent(content: content, revision: revision)
    }

    private func refreshUnifiedDiff() {
        let renamePairs = renamePairs()
        let pairedDestinations = Set(renamePairs.values)
        var handled = Set<TrackedPath>()
        var paths = Array(Set(baselineByPath.keys).union(currentByPath.keys))
        paths.sort { displayPath($0) < displayPath($1) }

        var previous = renderedDiffs
        var next: [DiffCacheKey: String?] = [:]
        var aggregated = ""
        for path in paths {
            guard handled.insert(path).inserted else { continue }
            if pairedDestinations.contains(path) { continue }
            let rightPath = renamePairs[path] ?? path
            if renamePairs[path] != nil {
                handled.insert(rightPath)
            }
            let leftPath = path
            let leftContent = baselineByPath[leftPath]
            let rightContent = currentByPath[rightPath]
            let key = DiffCacheKey(
                leftPath: leftPath,
                leftRevision: leftContent?.revision,
                rightPath: rightPath,
                rightRevision: rightContent?.revision
            )
            let rendered = previous.removeValue(forKey: key) ?? renderDiff(
                leftPath: leftPath,
                leftContent: leftContent?.content,
                rightPath: rightPath,
                rightContent: rightContent?.content
            )
            if let diff = rendered {
                aggregated += diff
                if !aggregated.hasSuffix("\n") {
                    aggregated += "\n"
                }
            }
            next[key] = rendered
        }
        renderedDiffs = next
        unifiedDiff = aggregated.isEmpty ? nil : aggregated
    }

    private func renamePairs() -> [TrackedPath: TrackedPath] {
        var pairs: [TrackedPath: TrackedPath] = [:]
        for (dest, origin) in originByCurrentPath {
            if dest == origin { continue }
            if currentByPath[origin] != nil { continue }
            if currentByPath[dest] == nil { continue }
            if baselineByPath[origin] == nil { continue }
            if baselineByPath[dest] != nil { continue }
            pairs[origin] = dest
        }
        return pairs
    }

    private func renderDiff(
        leftPath: TrackedPath,
        leftContent: String?,
        rightPath: TrackedPath,
        rightContent: String?
    ) -> String? {
        if leftContent == rightContent { return nil }
        guard leftContent != nil || rightContent != nil else { return nil }
        let leftDisplay = displayPath(leftPath).replacingOccurrences(of: "\\", with: "/")
        let rightDisplay = displayPath(rightPath).replacingOccurrences(of: "\\", with: "/")
        let leftOID = leftContent.map(gitBlobOID) ?? zeroOID
        let rightOID = rightContent.map(gitBlobOID) ?? zeroOID
        var diff = "diff --git a/\(leftDisplay) b/\(rightDisplay)\n"
        switch (leftContent, rightContent) {
        case (nil, .some):
            diff += "new file mode \(regularFileMode)\n"
        case (.some, nil):
            diff += "deleted file mode \(regularFileMode)\n"
        default:
            break
        }
        diff += "index \(leftOID)..\(rightOID)\n"
        let oldHeader = leftContent == nil ? devNull : "a/\(leftDisplay)"
        let newHeader = rightContent == nil ? devNull : "b/\(rightDisplay)"
        diff += unifiedLines(
            old: leftContent ?? "",
            new: rightContent ?? "",
            oldHeader: oldHeader,
            newHeader: newHeader
        )
        return diff
    }

    private func displayPath(_ path: TrackedPath) -> String {
        let display: String
        if let root = displayRootsByEnvironment[path.environmentId] {
            let rootPath = URL(fileURLWithPath: root).standardizedFileURL.path
            let full = path.path
            if full == rootPath {
                display = ""
            } else if full.hasPrefix(rootPath + "/") {
                display = String(full.dropFirst(rootPath.count + 1))
            } else {
                display = full
            }
        } else {
            display = path.path
        }
        if displayRootsByEnvironment.count > 1, !path.environmentId.isEmpty {
            return "\(path.environmentId)/\(display)"
        }
        return display
    }
}

func gitBlobOID(_ text: String) -> String {
    let data = Data(text.utf8)
    let header = Data("blob \(data.count)\u{0}".utf8)
    var hasher = Insecure.SHA1()
    hasher.update(data: header)
    hasher.update(data: data)
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func unifiedLines(old: String, new: String, oldHeader: String, newHeader: String) -> String {
    let oldLines = splitDiffLines(old)
    let newLines = splitDiffLines(new)
    var body = "--- \(oldHeader)\n+++ \(newHeader)\n"
    if oldLines.isEmpty {
        body += "@@ -0,0 +\(newLines.count == 0 ? 0 : 1),\(newLines.count) @@\n"
        for line in newLines {
            body += "+\(line)\n"
        }
        return body
    }
    if newLines.isEmpty {
        body += "@@ -1,\(oldLines.count) +0,0 @@\n"
        for line in oldLines {
            body += "-\(line)\n"
        }
        return body
    }
    body += "@@ -1,\(oldLines.count) +1,\(newLines.count) @@\n"
    let diff = newLines.difference(from: oldLines)
    var removals: Set<Int> = []
    var insertions: [Int: [String]] = [:]
    for change in diff {
        switch change {
        case .remove(let offset, let element, _):
            removals.insert(offset)
            _ = element
        case .insert(let offset, let element, _):
            insertions[offset, default: []].append(element)
        }
    }
    var oldIndex = 0
    var newIndex = 0
    while oldIndex < oldLines.count || newIndex < newLines.count {
        if removals.contains(oldIndex) {
            body += "-\(oldLines[oldIndex])\n"
            oldIndex += 1
            continue
        }
        if let extras = insertions[newIndex] {
            for line in extras {
                body += "+\(line)\n"
            }
            insertions[newIndex] = nil
            newIndex += extras.count
            continue
        }
        if oldIndex < oldLines.count, newIndex < newLines.count {
            body += " \(oldLines[oldIndex])\n"
            oldIndex += 1
            newIndex += 1
        } else {
            break
        }
    }
    return body
}

private func splitDiffLines(_ text: String) -> [String] {
    if text.isEmpty { return [] }
    var parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if text.hasSuffix("\n"), parts.last == "" {
        parts.removeLast()
    }
    return parts
}
