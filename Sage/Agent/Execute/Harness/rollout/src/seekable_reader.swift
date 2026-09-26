//
//  seekable_reader.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/seekable_reader.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Offsets still address original JSONL bytes. `.jsonl.zst` decoding waits
//  for `compression.swift`; a compressed-only file is an error, not a miss.
//

import CodexUtils
import Foundation

private let compressedSuffix = ".zst"
private let openRetryDelay: TimeInterval = 0.050

enum RolloutReader {
    case plain(FileHandle)

    static func open(_ path: String) throws -> RolloutReader {
        let plainPath = plainRolloutPath(path)
        let compressedPath = compressedSiblingPath(plainPath)
        for attempt in 0..<4 {
            if FileManager.default.isRegularFile(atPath: plainPath) {
                return .plain(try FileHandle(forReadingFrom: URL(fileURLWithPath: plainPath)))
            }
            if FileManager.default.isRegularFile(atPath: compressedPath) {
                throw IOError.other(
                    "compressed rollout is not supported until compression.swift is ported: \(compressedPath)"
                )
            }
            if attempt < 3 {
                Thread.sleep(forTimeInterval: openRetryDelay)
                continue
            }
            throw IOError.notFound(plainPath)
        }
        throw IOError.notFound(plainPath)
    }
}

/// Returns the plain `.jsonl` path for a plain or compressed rollout path.
public func plainRolloutPath(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    guard name.hasSuffix(compressedSuffix) else { return path }
    let plainName = String(name.dropLast(compressedSuffix.count))
    return ((path as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent(plainName)
}

func compressedSiblingPath(_ plainPath: String) -> String {
    let name = (plainPath as NSString).lastPathComponent
    if name.hasSuffix(".jsonl.zst") { return plainPath }
    return plainPath + compressedSuffix
}

/// Reads at most `maxBytes` decoded rollout bytes without materializing the durable file.
///
/// Returns `nil` for nonregular files.
public func readRolloutPrefix(path: String, maxBytes: Int) throws -> [UInt8]? {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
       isDirectory.boolValue
    {
        return nil
    }
    switch try RolloutReader.open(path) {
    case .plain(let handle):
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        return Array(data)
    }
}

/// Opens the original JSONL bytes for blocking offset reads without changing the rollout on disk.
public func openRolloutSeekableReader(path: String) throws -> FileHandle {
    switch try RolloutReader.open(path) {
    case .plain(let handle):
        return handle
    }
}

/// Checks a frozen prefix's byte bound using a blocking read of the logical JSONL representation.
public func rolloutContainsPrefix(path: String, endByteOffset: UInt64) throws -> Bool {
    switch try RolloutReader.open(path) {
    case .plain(let handle):
        defer { try? handle.close() }
        return endByteOffset <= (try handle.seekToEnd())
    }
}

extension FileManager {
    fileprivate func isRegularFile(atPath path: String) -> Bool {
        guard fileExists(atPath: path) else { return false }
        let attrs = try? attributesOfItem(atPath: path)
        if let type = attrs?[.type] as? FileAttributeType {
            return type == .typeRegular
        }
        return true
    }
}
