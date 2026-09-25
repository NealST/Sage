//
//  lib.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Apply parsed hunks to a local filesystem. Seatbelt / PathGuard live in the
//  tool handler, not here.
//

@_exported import FileSystem
import CodexUtils
import Foundation

public let CODEX_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR = "CODEX_APPLY_PATCH_PRESERVE_LINE_ENDINGS"

public enum ApplyPatchFileUpdateMode: Equatable {
    case normalizeToLf
    case preserveLineEndings
}

public struct ApplyPatchOptions: Equatable {
    public var updateFileMode: ApplyPatchFileUpdateMode
    public var followSymlinks: Bool

    public init(updateFileMode: ApplyPatchFileUpdateMode, followSymlinks: Bool) {
        self.updateFileMode = updateFileMode
        self.followSymlinks = followSymlinks
    }

    public static let `default` = ApplyPatchOptions(
        updateFileMode: .normalizeToLf,
        followSymlinks: true
    )
}

public enum ApplyPatchError: Error, Equatable, LocalizedError {
    case parse(ParseError)
    case io(context: String, message: String)
    case computeReplacements(String)

    public var errorDescription: String? {
        switch self {
        case .parse(let error):
            return error.localizedDescription
        case .io(let context, let message):
            return "\(context): \(message)"
        case .computeReplacements(let message):
            return message
        }
    }
}

public struct ApplyPatchArgs: Equatable {
    public var patch: String
    public var hunks: [Hunk]
    public var workdir: String?
    public var environmentID: String?

    public init(patch: String, hunks: [Hunk], workdir: String?, environmentID: String?) {
        self.patch = patch
        self.hunks = hunks
        self.workdir = workdir
        self.environmentID = environmentID
    }
}

/// Proposed filesystem change parsed from an `apply_patch` invocation.
public enum ApplyPatchFileChange: Equatable {
    case add(content: String)
    case delete(content: String)
    case update(unifiedDiff: String, movePath: PathUri?, newContent: String)
}

/// Verified `apply_patch` action. Paths are absolute by construction.
public struct ApplyPatchAction: Equatable {
    public var patch: String
    public var cwd: PathUri
    var fileChanges: [PathUri: ApplyPatchFileChange]
    var updateFileMode: ApplyPatchFileUpdateMode

    public init(
        patch: String,
        cwd: PathUri,
        changes: [PathUri: ApplyPatchFileChange],
        updateFileMode: ApplyPatchFileUpdateMode = .normalizeToLf
    ) {
        self.patch = patch
        self.cwd = cwd
        self.fileChanges = changes
        self.updateFileMode = updateFileMode
    }

    public var isEmpty: Bool { fileChanges.isEmpty }

    public func changes() -> [PathUri: ApplyPatchFileChange] { fileChanges }

    public func updateFileModeValue() -> ApplyPatchFileUpdateMode { updateFileMode }

    public static func newAddForTest(path: PathUri, content: String) -> ApplyPatchAction {
        let filename = path.basename() ?? "file"
        let patch = """
        *** Begin Patch
        *** Update File: \(filename)
        +\(content)
        *** End Patch
        """
        return ApplyPatchAction(
            patch: patch,
            cwd: path,
            changes: [path: .add(content: content)]
        )
    }
}

struct AffectedPaths: Equatable {
    var added: [String] = []
    var modified: [String] = []
    var deleted: [String] = []
}

public struct AppliedPatchChange: Equatable {
    public var path: URL
    public var kind: AppliedPatchFileChange

    public init(path: URL, kind: AppliedPatchFileChange) {
        self.path = path
        self.kind = kind
    }
}

public enum AppliedPatchFileChange: Equatable {
    case add(content: String, overwrittenContent: String?)
    case delete(content: String)
    case update(movePath: URL?, oldContent: String, overwrittenMoveContent: String?, newContent: String)
}

public struct AppliedPatchDelta: Equatable {
    public var changes: [AppliedPatchChange] = []
    public var exact = true

    public init(changes: [AppliedPatchChange] = [], exact: Bool = true) {
        self.changes = changes
        self.exact = exact
    }

    public var isEmpty: Bool { changes.isEmpty }
}

public struct ApplyPatchFailure: Error, LocalizedError {
    public var error: ApplyPatchError
    public var delta: AppliedPatchDelta

    public init(error: ApplyPatchError, delta: AppliedPatchDelta) {
        self.error = error
        self.delta = delta
    }

    public var errorDescription: String? { error.localizedDescription }
}

public protocol ApplyPatchFileSystem {
    func readFileText(_ url: URL) throws -> String
    func writeFile(_ url: URL, contents: String) throws
    func createDirectory(_ url: URL) throws
    func removeFile(_ url: URL) throws
    func metadata(_ url: URL) throws -> ApplyPatchMetadata
}

public struct ApplyPatchMetadata: Equatable {
    var exists: Bool
    var isFile: Bool
    var isDirectory: Bool
    var isSymlink: Bool
}

public enum LocalApplyPatchFileSystem: ApplyPatchFileSystem {
    case shared

    public func readFileText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ApplyPatchError.io(context: "Failed to read file \(url.path)", message: "not UTF-8")
        }
        return text
    }

    public func writeFile(_ url: URL, contents: String) throws {
        try contents.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func removeFile(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func metadata(_ url: URL) throws -> ApplyPatchMetadata {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if !exists {
            return ApplyPatchMetadata(exists: false, isFile: false, isDirectory: false, isSymlink: false)
        }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        return ApplyPatchMetadata(
            exists: true,
            isFile: values.isRegularFile == true,
            isDirectory: isDirectory.boolValue,
            isSymlink: values.isSymbolicLink == true
        )
    }
}

public func applyPatch(
    _ patch: String,
    cwd: URL,
    options: ApplyPatchOptions = .default
) throws -> (delta: AppliedPatchDelta, summary: String) {
    try applyPatch(
        patch,
        cwd: cwd,
        options: options,
        fileSystem: LocalApplyPatchFileSystem.shared
    )
}

func applyPatch(
    _ patch: String,
    cwd: URL,
    options: ApplyPatchOptions = .default,
    fileSystem: ApplyPatchFileSystem
) throws -> (delta: AppliedPatchDelta, summary: String) {
    let parsed: ApplyPatchArgs
    do {
        parsed = try parsePatch(patch)
    } catch let error as ParseError {
        throw ApplyPatchFailure(error: .parse(error), delta: AppliedPatchDelta())
    }
    return try applyHunks(parsed.hunks, cwd: cwd, options: options, fileSystem: fileSystem)
}

public func applyHunks(
    _ hunks: [Hunk],
    cwd: URL,
    options: ApplyPatchOptions = .default,
    fileSystem: ApplyPatchFileSystem? = nil
) throws -> (delta: AppliedPatchDelta, summary: String) {
    try applyHunks(
        hunks,
        cwd: cwd,
        options: options,
        fileSystem: fileSystem ?? LocalApplyPatchFileSystem.shared
    )
}

func applyHunks(
    _ hunks: [Hunk],
    cwd: URL,
    options: ApplyPatchOptions = .default,
    fileSystem: ApplyPatchFileSystem
) throws -> (delta: AppliedPatchDelta, summary: String) {
    var delta = AppliedPatchDelta()
    do {
        let affected = try applyHunksToFiles(
            hunks,
            cwd: cwd,
            options: options,
            fileSystem: fileSystem,
            delta: &delta
        )
        return (delta, printSummary(affected))
    } catch let failure as ApplyPatchFailure {
        throw failure
    } catch let error as ApplyPatchError {
        throw ApplyPatchFailure(error: error, delta: delta)
    } catch {
        throw ApplyPatchFailure(
            error: .io(context: "I/O error", message: error.localizedDescription),
            delta: delta
        )
    }
}

func applyHunksToFiles(
    _ hunks: [Hunk],
    cwd: URL,
    options: ApplyPatchOptions,
    fileSystem: ApplyPatchFileSystem,
    delta: inout AppliedPatchDelta
) throws -> AffectedPaths {
    guard !hunks.isEmpty else {
        throw ApplyPatchError.computeReplacements("No files were modified.")
    }

    var added: [String] = []
    var modified: [String] = []
    var deleted: [String] = []

    for hunk in hunks {
        let displayed = hunk.path()
        let path = hunk.resolveSourcePath(cwd: cwd)
        switch hunk {
        case .addFile(_, let contents):
            let overwritten = try? fileSystem.readFileText(path)
            try writeFileCreatingParents(path, contents: contents, fileSystem: fileSystem, delta: &delta)
            delta.changes.append(
                AppliedPatchChange(path: path, kind: .add(content: contents, overwrittenContent: overwritten))
            )
            added.append(displayed)

        case .deleteFile:
            try ensureNotDirectory(path, fileSystem: fileSystem)
            let deletedContent = try fileSystem.readFileText(path)
            try fileSystem.removeFile(path)
            delta.changes.append(AppliedPatchChange(path: path, kind: .delete(content: deletedContent)))
            deleted.append(displayed)

        case .updateFile(_, let movePath, let chunks):
            let applied = try deriveNewContentsFromChunks(
                path: path,
                chunks: chunks,
                updateFileMode: options.updateFileMode,
                fileSystem: fileSystem
            )
            if let dest = movePath {
                let destURL = ApplyPatchPaths.resolve(dest, cwd: cwd)
                let overwrittenMove = try? fileSystem.readFileText(destURL)
                try writeFileCreatingParents(
                    destURL,
                    contents: applied.newContents,
                    fileSystem: fileSystem,
                    delta: &delta
                )
                try ensureNotDirectory(path, fileSystem: fileSystem)
                try fileSystem.removeFile(path)
                delta.changes.append(
                    AppliedPatchChange(
                        path: path,
                        kind: .update(
                            movePath: destURL,
                            oldContent: applied.originalContents,
                            overwrittenMoveContent: overwrittenMove,
                            newContent: applied.newContents
                        )
                    )
                )
                modified.append(displayed)
            } else {
                try fileSystem.writeFile(path, contents: applied.newContents)
                delta.changes.append(
                    AppliedPatchChange(
                        path: path,
                        kind: .update(
                            movePath: nil,
                            oldContent: applied.originalContents,
                            overwrittenMoveContent: nil,
                            newContent: applied.newContents
                        )
                    )
                )
                modified.append(displayed)
            }
        }
    }

    return AffectedPaths(added: added, modified: modified, deleted: deleted)
}

func printSummary(_ affected: AffectedPaths) -> String {
    var lines = ["Success. Updated the following files:"]
    for path in affected.added { lines.append("A \(path)") }
    for path in affected.modified { lines.append("M \(path)") }
    for path in affected.deleted { lines.append("D \(path)") }
    return lines.joined(separator: "\n") + "\n"
}

private func writeFileCreatingParents(
    _ url: URL,
    contents: String,
    fileSystem: ApplyPatchFileSystem,
    delta: inout AppliedPatchDelta
) throws {
    do {
        try fileSystem.writeFile(url, contents: contents)
    } catch {
        let parent = url.deletingLastPathComponent()
        do {
            try fileSystem.createDirectory(parent)
            try fileSystem.writeFile(url, contents: contents)
        } catch {
            delta.exact = false
            throw error
        }
    }
}

public struct SandboxedApplyPatchFileSystem: ApplyPatchFileSystem {
    private let inner: any ApplyPatchFileSystem
    private let sandbox: FileSystemSandboxContext

    public init(
        inner: any ApplyPatchFileSystem = LocalApplyPatchFileSystem.shared,
        sandbox: FileSystemSandboxContext
    ) {
        self.inner = inner
        self.sandbox = sandbox
    }

    public func readFileText(_ url: URL) throws -> String {
        try check(url, write: false)
        return try inner.readFileText(url)
    }

    public func writeFile(_ url: URL, contents: String) throws {
        try check(url, write: true)
        try inner.writeFile(url, contents: contents)
    }

    public func createDirectory(_ url: URL) throws {
        try check(url, write: true)
        try inner.createDirectory(url)
    }

    public func removeFile(_ url: URL) throws {
        try check(url, write: true)
        try inner.removeFile(url)
    }

    public func metadata(_ url: URL) throws -> ApplyPatchMetadata {
        try check(url, write: false)
        return try inner.metadata(url)
    }

    private func check(_ url: URL, write: Bool) throws {
        do {
            try sandbox.assertAllowed(url, write: write)
        } catch let error as FileSystemSandboxError {
            switch error {
            case .notPermitted(let path, let writing):
                let verb = writing ? "write" : "access"
                throw ApplyPatchError.io(
                    context: "Failed to \(verb) \(path)",
                    message: "Operation not permitted"
                )
            }
        }
    }
}

private func ensureNotDirectory(_ url: URL, fileSystem: ApplyPatchFileSystem) throws {
    let metadata = try fileSystem.metadata(url)
    if metadata.isDirectory {
        throw ApplyPatchError.io(context: "Failed to delete file \(url.path)", message: "path is a directory")
    }
}
