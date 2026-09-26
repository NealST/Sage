//
//  ordinal.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/ordinal.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resume scans the last parsed JSONL line instead of ReverseJsonlScanner
//  until that file is ported.
//

import CodexHistory
import CodexProtocol
import Foundation

enum RolloutOrdinalState: Equatable, Sendable {
    case legacy
    case paginated(next: UInt64?)

    static func forNewRollout(
        historyMode: ThreadHistoryMode,
        historyBase: HistoryPosition?
    ) -> RolloutOrdinalState {
        switch historyMode {
        case .legacy:
            return .legacy
        case .paginated:
            return .paginated(next: historyBase?.endOrdinalExclusive ?? 0)
        }
    }

    func current() throws -> UInt64? {
        switch self {
        case .legacy:
            return nil
        case .paginated(let next):
            guard let ordinal = next else {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(EIO),
                    userInfo: [NSLocalizedDescriptionKey: "paginated rollout record ordinal overflow"]
                )
            }
            return ordinal
        }
    }

    mutating func advance() {
        if case .paginated(let next) = self, let ordinal = next {
            self = .paginated(next: ordinal + 1)
        }
    }
}

func ordinalStateForRollout(at path: URL) throws -> RolloutOrdinalState {
    let handle = try FileHandle(forReadingFrom: path)
    defer { try? handle.close() }
    guard let metadata = try readHistoryMetadata(handle: handle, path: path) else {
        return .legacy
    }
    if metadata.historyMode == .legacy {
        return .legacy
    }

    let data = try Data(contentsOf: path)
    var last: RolloutLine?
    for raw in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
        let line = String(decoding: raw, as: UTF8.self)
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        do {
            last = try parseRolloutLine(line)
        } catch {
            continue
        }
    }
    guard let record = last else {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EIO),
            userInfo: [NSLocalizedDescriptionKey: "rollout at \(path.path) contains no valid records"]
        )
    }
    guard let ordinal = record.ordinal else {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EIO),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "final paginated rollout record at \(path.path) is missing an ordinal"
            ]
        )
    }
    if let start = metadata.subagentHistoryStartOrdinal, start > 0, ordinal < start - 1 {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EIO),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "paginated subagent rollout at \(path.path) is incomplete: expected inherited prefix through ordinal \(start - 1), found final durable ordinal \(ordinal)"
            ]
        )
    }
    return .paginated(next: ordinal + 1)
}

private struct HistoryMetadata {
    var historyMode: ThreadHistoryMode
    var subagentHistoryStartOrdinal: UInt64?
}

private func readHistoryMetadata(handle: FileHandle, path: URL) throws -> HistoryMetadata? {
    try handle.seek(toOffset: 0)
    let data = handle.readDataToEndOfFile()
    for raw in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
        let line = String(decoding: raw, as: UTF8.self)
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let record = try parseRolloutLine(line)
        guard case .sessionMeta(let sessionMeta) = record.item else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(EIO),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "rollout at \(path.path) does not start with session metadata"
                ]
            )
        }
        return HistoryMetadata(
            historyMode: sessionMeta.meta.historyMode,
            subagentHistoryStartOrdinal: sessionMeta.meta.subagentHistoryStartOrdinal
        )
    }
    return nil
}
