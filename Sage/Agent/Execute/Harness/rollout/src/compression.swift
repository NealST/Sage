//
//  compression.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/compression.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Path helpers and plain `.jsonl` line reading are faithful. `.jsonl.zst`
//  decode / background worker wait for a zstd binding; compressed-only
//  files throw rather than silently skipping.
//

import Foundation

public let COMPRESSED_SUFFIX = ".zst"

/// The entry point that requested a compression pass, not a Statsig cohort.
public enum RolloutCompressionTrigger: Sendable {
    case startup
    case rpc

    var tag: String {
        switch self {
        case .startup: return "startup"
        case .rpc: return "rpc"
        }
    }
}

/// Starts a best-effort background job that compresses cold local rollout files.
///
/// Fire-and-forget in Rust. Here the worker is a no-op until zstd lands.
public func spawnRolloutCompressionWorker(codexHome: String, trigger: RolloutCompressionTrigger) {
    _ = (codexHome, trigger)
}

/// A discovered rollout file, represented by exactly one physical path.
public struct RolloutFile: Equatable, Sendable {
    public var path: String
    public var plainFileName: String

    public var isCompressed: Bool {
        (path as NSString).lastPathComponent.hasSuffix(".jsonl.zst")
    }

    public static func fromPath(_ path: String) -> RolloutFile? {
        let fileName = (path as NSString).lastPathComponent
        guard let plainFileName = parseRolloutFileName(fileName) else { return nil }
        if shouldSkipCompressedSibling(path) { return nil }
        return RolloutFile(path: path, plainFileName: plainFileName)
    }
}

/// Returns the plain `.jsonl` path for a plain or compressed rollout path.
public func compressionPlainRolloutPath(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    guard name.hasSuffix(COMPRESSED_SUFFIX) else { return path }
    let plainName = String(name.dropLast(COMPRESSED_SUFFIX.count))
    return ((path as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent(plainName)
}

public func compressedRolloutPath(_ path: String) -> String {
    if isCompressedRolloutPath(path) { return path }
    return path + COMPRESSED_SUFFIX
}

public func isCompressedRolloutPath(_ path: String) -> Bool {
    (path as NSString).lastPathComponent.hasSuffix(".jsonl.zst")
}

public func shouldSkipCompressedSibling(_ path: String) -> Bool {
    isCompressedRolloutPath(path)
        && FileManager.default.fileExists(atPath: compressionPlainRolloutPath(path))
}

/// Returns the existing rollout path, preferring the plain `.jsonl` file.
public func existingRolloutPath(_ path: String) -> String? {
    let plain = compressionPlainRolloutPath(path)
    if FileManager.default.isRegularFile(atPath: plain) { return plain }
    let compressed = compressedRolloutPath(plain)
    if FileManager.default.isRegularFile(atPath: compressed) { return compressed }
    return nil
}

/// Materializes a compressed rollout as plain JSONL. Plain files are returned as-is.
public func materializeRolloutForAppend(_ path: String) throws -> String {
    let plain = compressionPlainRolloutPath(path)
    if FileManager.default.fileExists(atPath: plain) { return plain }
    if FileManager.default.fileExists(atPath: compressedRolloutPath(plain)) {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(ENOSYS),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "compressed rollout materialize requires zstd: \(compressedRolloutPath(plain))"
            ]
        )
    }
    return plain
}

/// Line reader that transparently handles plain `.jsonl`. Compressed-only is an error.
public struct RolloutLineReader {
    private var lines: [String]
    private var index = 0

    public init(path: String) throws {
        let resolved = try resolveReadableRollout(path)
        let text = try String(contentsOfFile: resolved, encoding: .utf8)
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
    }

    public mutating func nextLine() -> String? {
        guard index < lines.count else { return nil }
        defer { index += 1 }
        return lines[index]
    }
}

public func openRolloutLineReader(path: String) throws -> RolloutLineReader {
    try RolloutLineReader(path: path)
}

private func resolveReadableRollout(_ path: String) throws -> String {
    if let existing = existingRolloutPath(path) {
        if isCompressedRolloutPath(existing) {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(ENOSYS),
                userInfo: [
                    NSLocalizedDescriptionKey: "compressed rollout is not supported yet: \(existing)"
                ]
            )
        }
        return existing
    }
    throw NSError(
        domain: NSCocoaErrorDomain,
        code: NSFileNoSuchFileError,
        userInfo: [NSLocalizedDescriptionKey: path]
    )
}

extension FileManager {
    fileprivate func isRegularFile(atPath path: String) -> Bool {
        guard fileExists(atPath: path) else { return false }
        if let type = (try? attributesOfItem(atPath: path))?[.type] as? FileAttributeType {
            return type == .typeRegular
        }
        return true
    }
}
