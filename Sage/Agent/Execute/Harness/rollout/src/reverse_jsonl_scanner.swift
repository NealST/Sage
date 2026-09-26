//
//  reverse_jsonl_scanner.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/reverse_jsonl_scanner.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Blocking `Read + Seek` maps to `FileHandle`. JSONL record boundaries and
//  oversized-record skipping match the Rust scanner.
//

import CodexHistory
import CodexProtocol
import CodexUtils
import Foundation

private let readChunkSize = 64 * 1024

public enum ScanOutcome<T> {
    /// The record was valid JSON and deserialized as the requested type.
    case parsed(T)
    /// The record was not valid JSON for the requested type.
    case rejected(any Error)
}

/// Read-only scanner for newline-delimited JSON records, starting from the end.
public final class ReverseJsonlScanner {
    private var reader: FileHandle
    private var nextChunkEnd: UInt64
    private var chunkPosition: Int
    private var chunk: [UInt8]
    private var recordReversed: [UInt8]
    private var maxRecordBytes: Int?
    private var discardingOversizedRecord = false

    public convenience init(_ reader: FileHandle) throws {
        let nextChunkEnd = try reader.seekToEnd()
        try self.init(reader, endByteOffset: nextChunkEnd)
    }

    /// Creates a reverse scanner whose logical end is the given byte offset.
    ///
    /// This lets callers scan a frozen JSONL prefix without reading records appended after that
    /// prefix was captured.
    public init(_ reader: FileHandle, endByteOffset: UInt64) throws {
        let fileLen = try reader.seekToEnd()
        if endByteOffset > fileLen {
            throw IOError.invalidInput("reverse JSONL scan end is past the file")
        }
        self.reader = reader
        self.nextChunkEnd = endByteOffset
        self.chunkPosition = 0
        self.chunk = Array(repeating: 0, count: readChunkSize)
        self.recordReversed = []
        self.maxRecordBytes = nil
        self.discardingOversizedRecord = false
    }

    /// Skips records larger than the configured limit without buffering or parsing them.
    public func withMaxRecordBytes(_ maxRecordBytes: Int) -> ReverseJsonlScanner {
        self.maxRecordBytes = maxRecordBytes
        return self
    }

    /// Scans the next nonblank record.
    ///
    /// I/O failures are thrown. Invalid JSON records are returned as
    /// `ScanOutcome.rejected`, and the scanner remains usable.
    public func scanNext<T: Decodable>() throws -> ScanOutcome<T>? {
        while true {
            if chunkPosition == 0 {
                if nextChunkEnd == 0 {
                    if discardingOversizedRecord {
                        discardingOversizedRecord = false
                        return nil
                    }
                    return try finishRecord()
                }

                let readSize64 = min(nextChunkEnd, UInt64(readChunkSize))
                guard let readSize = Int(exactly: readSize64) else {
                    throw IOError.other("reverse JSONL chunk size overflow")
                }
                nextChunkEnd -= UInt64(readSize)
                try reader.seek(toOffset: nextChunkEnd)
                let data = try reader.read(upToCount: readSize) ?? Data()
                if data.count != readSize {
                    throw IOError.other("failed to read a full reverse JSONL chunk")
                }
                chunk.withUnsafeMutableBytes { dest in
                    data.copyBytes(to: dest, count: readSize)
                }
                chunkPosition = readSize
            }

            let chunkView = chunk[..<chunkPosition]
            if let newlinePosition = chunkView.lastIndex(of: UInt8(ascii: "\n")) {
                let fragment = Array(chunkView[(newlinePosition + 1)...])
                appendFragment(fragment)
                chunkPosition = newlinePosition
                if discardingOversizedRecord {
                    discardingOversizedRecord = false
                    continue
                }
                if let outcome: ScanOutcome<T> = try finishRecord() {
                    return outcome
                }
            } else {
                appendFragment(Array(chunkView))
                chunkPosition = 0
            }
        }
    }

    /// Scans the next rollout record through the canonical persisted JSON decoder.
    public func scanNextRolloutLine() throws -> ScanOutcome<RolloutLine>? {
        guard let outcome: ScanOutcome<JSONValue> = try scanNext() else { return nil }
        switch outcome {
        case .parsed(let value):
            do {
                return .parsed(try decodeRolloutLine(value))
            } catch {
                return .rejected(error)
            }
        case .rejected(let error):
            return .rejected(error)
        }
    }

    private func appendFragment(_ fragment: [UInt8]) {
        guard !discardingOversizedRecord else { return }
        if let maxRecordBytes, saturatingAdd(recordReversed.count, fragment.count) > maxRecordBytes {
            recordReversed.removeAll()
            discardingOversizedRecord = true
        } else {
            recordReversed.append(contentsOf: fragment.reversed())
        }
    }

    private func finishRecord<T: Decodable>() throws -> ScanOutcome<T>? {
        recordReversed.reverse()
        let outcome: ScanOutcome<T>?
        if recordReversed.allSatisfy(isASCIIWhitespace) {
            outcome = nil
        } else {
            do {
                let value = try JSONDecoder().decode(T.self, from: Data(recordReversed))
                outcome = .parsed(value)
            } catch {
                outcome = .rejected(error)
            }
        }
        recordReversed.removeAll()
        return outcome
    }
}

private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : result
}

private func isASCIIWhitespace(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20:
        return true
    default:
        return false
    }
}
