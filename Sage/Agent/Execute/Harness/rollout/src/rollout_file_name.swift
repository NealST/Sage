//
//  rollout_file_name.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/rollout_file_name.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `time` crate formatting maps to `DateFormatter` with a fixed UTC pattern.
//

import CodexProtocol
import Foundation

private let compressedSuffix = ".zst"
private let timestampFormat = "yyyy-MM-dd'T'HH-mm-ss"

/// Parsed canonical rollout basename.
///
/// Ordinary rollout filenames encode one ID, which is both the thread ID and rollout ID.
/// Filenames for reverted threads append an underscore and a distinct rollout ID after the stable
/// thread ID.
public struct RolloutFileName: Equatable, Sendable {
    public var timestamp: Date
    public var threadId: ThreadId
    public var rolloutId: RolloutId

    public init(timestamp: Date, threadId: ThreadId, rolloutId: RolloutId) {
        self.timestamp = timestamp
        self.threadId = threadId
        self.rolloutId = rolloutId
    }

    public static func parse(_ name: String) -> RolloutFileName? {
        guard let plain = parseRolloutFileName(name) else { return nil }
        guard let core = plain.dropPrefix("rollout-")?.dropSuffix(".jsonl") else { return nil }
        guard core.count >= 20 else { return nil }
        let timestampRaw = String(core.prefix(19))
        guard core.dropFirst(19).first == "-" else { return nil }
        let ids = String(core.dropFirst(20))
        let parts = ids.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        let threadRaw = String(parts[0])
        let rolloutRaw = parts.count > 1 ? String(parts[1]) : threadRaw
        guard let threadId = try? ThreadId.fromString(threadRaw),
              let rolloutId = try? RolloutId.fromString(rolloutRaw)
        else { return nil }
        let formatter = utcFormatter()
        guard let timestamp = formatter.date(from: timestampRaw) else { return nil }
        return RolloutFileName(timestamp: timestamp, threadId: threadId, rolloutId: rolloutId)
    }

    public func render() -> String {
        let timestamp = utcFormatter().string(from: timestamp)
        if threadId == rolloutId {
            return "rollout-\(timestamp)-\(threadId).jsonl"
        }
        return "rollout-\(timestamp)-\(threadId)_\(rolloutId).jsonl"
    }
}

func parseRolloutFileName(_ name: String) -> String? {
    let stripped = name.hasSuffix(compressedSuffix)
        ? String(name.dropLast(compressedSuffix.count))
        : name
    if stripped.hasPrefix("rollout-"), stripped.hasSuffix(".jsonl") {
        return stripped
    }
    return nil
}

private func utcFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = timestampFormat
    return formatter
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    func dropSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else { return nil }
        return String(dropLast(suffix.count))
    }
}
