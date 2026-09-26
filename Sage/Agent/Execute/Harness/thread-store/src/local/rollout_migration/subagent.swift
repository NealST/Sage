//
//  subagent.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/subagent.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Reverse JSONL scan uses CodexRollout's FileHandle scanner. Tokio
//  `spawn_blocking` is omitted.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

func selectBoundedContext(rolloutPath: String) throws -> [RolloutItem]? {
    let handle: FileHandle
    do {
        handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: rolloutPath))
    } catch {
        throw migrationError(error)
    }
    defer { try? handle.close() }
    let scanner: ReverseJsonlScanner
    do {
        scanner = try ReverseJsonlScanner(handle).withMaxRecordBytes(MAX_ROLLOUT_LINE_BYTES)
    } catch {
        throw migrationError(error)
    }
    var scan = ModelContextScan()
    while true {
        let outcome: ScanOutcome<JSONValue>
        do {
            guard let next = try scanner.scanNext() as ScanOutcome<JSONValue>? else { break }
            outcome = next
        } catch {
            throw migrationError(error)
        }
        let value: JSONValue
        switch outcome {
        case .parsed(let parsed):
            value = parsed
        case .rejected:
            continue
        }
        guard case .success(let line?) = parseLegacyRolloutValue(value) else { continue }
        if scan.push(line.item) == .complete {
            var items = scan.finish()
            items.removeAll { item in
                if case .sessionMeta = item { return true }
                return false
            }
            return items
        }
    }
    return nil
}
