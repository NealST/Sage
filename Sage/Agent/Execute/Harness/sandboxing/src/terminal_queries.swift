//
//  terminal_queries.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/terminal_queries.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The query/response state machine is faithful. The spawned-process
//  interceptor waits on utils/pty (`SpawnedProcess`) which is not ported
//  yet; `respondToTerminalQueries` is a pass-through until that crate
//  lands.
//

import Foundation

let QUERY_RESPONSES: [(query: [UInt8], response: [UInt8])] = [
    ([0x1b, 0x5b, 0x35, 0x6e], [0x1b, 0x5b, 0x30, 0x6e]),
    ([0x1b, 0x5b, 0x31, 0x38, 0x74], [0x1b, 0x5b, 0x38, 0x3b, 0x32, 0x34, 0x3b, 0x38, 0x30, 0x74]),
    ([0x1b, 0x5b, 0x36, 0x6e], [0x1b, 0x5b, 0x31, 0x3b, 0x31, 0x52]),
]
let MAX_MODE_DIGITS = 10
let MAX_QUERY_BYTES = MAX_MODE_DIGITS + 5

struct TerminalQueryResponder {
    var pending: [UInt8] = []

    mutating func process(_ bytes: [UInt8]) -> (output: [UInt8], responses: [UInt8]) {
        if pending.isEmpty && !bytes.contains(0x1b) {
            return (bytes, [])
        }
        var output: [UInt8] = []
        var responses: [UInt8] = []
        output.reserveCapacity(bytes.count)

        for byte in bytes {
            if pending.isEmpty && byte != 0x1b {
                output.append(byte)
                continue
            }
            if byte == 0x1b {
                output.append(contentsOf: pending)
                pending.removeAll()
            }
            pending.append(byte)
            if pending.count == 1
                || pending == [0x1b, 0x5b]
                || (pending.count >= 2 && pending[1] == 0x5b
                    && !(0x40...0x7e).contains(byte)
                    && pending.count < MAX_QUERY_BYTES) {
                continue
            }

            if let match = QUERY_RESPONSES.first(where: { $0.query == pending }) {
                responses.append(contentsOf: match.response)
            } else if pending.count >= 4,
                      pending[0] == 0x1b,
                      pending[1] == 0x5b,
                      pending[2] == 0x3f,
                      pending[pending.count - 2] == 0x24,
                      pending[pending.count - 1] == 0x70 {
                let mode = Array(pending.dropFirst(3).dropLast(2))
                if !mode.isEmpty,
                   mode.count <= MAX_MODE_DIGITS,
                   mode.allSatisfy({ (0x30...0x39).contains($0) }) {
                    responses.append(contentsOf: [0x1b, 0x5b, 0x3f])
                    responses.append(contentsOf: mode)
                    responses.append(contentsOf: [0x3b, 0x30, 0x24, 0x79])
                } else {
                    output.append(contentsOf: pending)
                }
            } else {
                output.append(contentsOf: pending)
            }
            pending.removeAll()
        }
        return (output, responses)
    }
}

/// Pass-through until `utils/pty` `SpawnedProcess` is ported.
public func respondToTerminalQueries<T>(_ spawned: T) -> T {
    spawned
}
