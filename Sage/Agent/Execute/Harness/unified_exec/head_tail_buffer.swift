//
//  head_tail_buffer.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/head_tail_buffer.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Const generic MAX_BYTES is a stored cap; default matches
//  UNIFIED_EXEC_OUTPUT_MAX_BYTES.
//

import Foundation

struct HeadTailBuffer: Equatable {
    private var head = Data()
    private var tail = Data()
    private(set) var omittedBytes = 0
    var maxBytes: Int

    var headBudget: Int { maxBytes / 2 }
    var tailBudget: Int { max(0, maxBytes - headBudget) }

    init(maxBytes: Int = UNIFIED_EXEC_OUTPUT_MAX_BYTES) {
        self.maxBytes = maxBytes
    }

    var retainedBytes: Int { head.count + tail.count }

    var totalBytes: Int { retainedBytes + omittedBytes }

    mutating func pushChunk(_ chunk: Data) {
        let overflow = fillHead(chunk)
        pushTail(overflow)
    }

    @discardableResult
    private mutating func fillHead(_ chunk: Data) -> Data {
        let remainingHead = max(0, headBudget - head.count)
        if remainingHead == 0 { return chunk }
        if chunk.count <= remainingHead {
            head.append(chunk)
            return Data()
        }
        head.append(chunk.prefix(remainingHead))
        return Data(chunk.dropFirst(remainingHead))
    }

    private mutating func pushTail(_ chunk: Data) {
        let remainingTail = max(0, tailBudget - tail.count)
        let excessTail = max(0, chunk.count - remainingTail)
        omittedBytes += excessTail
        if excessTail < tail.count {
            if excessTail > 0 {
                tail.removeFirst(excessTail)
            }
            tail.append(chunk)
        } else {
            let skip = excessTail - tail.count
            tail.removeAll()
            if skip < chunk.count {
                tail.append(chunk.dropFirst(skip))
            }
        }
    }

    func toBytes() -> Data {
        var out = Data(capacity: retainedBytes)
        out.append(head)
        out.append(tail)
        return out
    }

    func toBytesWithOmissionMarker() -> Data {
        if omittedBytes == 0 { return toBytes() }
        let marker = formatOutputOmissionMarker(omittedBytes)
        var out = Data()
        out.append(head)
        out.append(contentsOf: [UInt8(ascii: "\n")])
        out.append(Data(marker.utf8))
        out.append(contentsOf: [UInt8(ascii: "\n")])
        out.append(tail)
        return out
    }

    mutating func pushBuffer(_ buffer: HeadTailBuffer) {
        omittedBytes += buffer.omittedBytes
        let overflow: Data
        if head.isEmpty {
            head = buffer.head
            overflow = Data()
        } else {
            overflow = fillHead(buffer.head)
        }
        if buffer.tail.count == tailBudget {
            omittedBytes += tail.count + overflow.count
            tail = buffer.tail
        } else {
            pushTail(overflow)
            if tail.isEmpty {
                tail = buffer.tail
            } else {
                pushTail(buffer.tail)
            }
        }
    }
}
