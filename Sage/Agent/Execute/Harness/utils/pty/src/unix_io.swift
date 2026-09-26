//
//  unix_io.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/unix_io.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Non-blocking PTY master I/O via DispatchIO instead of Tokio AsyncFd.
//  Stdin-close VEOF matches portable-pty (newline + current VEOF).
//

import Darwin
import Foundation

enum StdinCloseBehavior {
    case sendEof
    case noEof
}

final class PtyIo {
    let masterFd: Int32

    init(masterFd: Int32) throws {
        let flags = fcntl(masterFd, F_GETFL)
        if flags == -1 || fcntl(masterFd, F_SETFL, flags | O_NONBLOCK) == -1 {
            throw posixError()
        }
        self.masterFd = masterFd
    }

    func spawn(
        stdout: AsyncStream<Data>.Continuation,
        writer: AsyncStream<Data>,
        stdinClose: StdinCloseBehavior
    ) -> (Task<Void, Never>, Task<Void, Never>) {
        let fd = masterFd
        let reader = Task {
            var buffer = [UInt8](repeating: 0, count: 8192)
            while !Task.isCancelled {
                let n = buffer.withUnsafeMutableBytes { ptr in
                    Darwin.read(fd, ptr.baseAddress, ptr.count)
                }
                if n == 0 { break }
                if n < 0 {
                    if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                        try? await Task.sleep(nanoseconds: 8_000_000)
                        continue
                    }
                    break
                }
                stdout.yield(Data(buffer.prefix(n)))
            }
            stdout.finish()
        }
        let writerTask = Task {
            for await chunk in writer {
                if writeAll(fd, chunk) == false { break }
            }
            if case .sendEof = stdinClose {
                var term = termios()
                if tcgetattr(fd, &term) == 0 {
                    let eof = withUnsafePointer(to: &term.c_cc) { ptr in
                        ptr.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { $0[Int(VEOF)] }
                    }
                    if eof != 0 {
                        _ = writeAll(fd, Data([UInt8(ascii: "\n"), eof]))
                    }
                }
            }
        }
        return (reader, writerTask)
    }
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    var offset = 0
    return data.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        while offset < bytes.count {
            let n = Darwin.write(fd, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
            if n == 0 { return false }
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(8000)
                    continue
                }
                return false
            }
            offset += n
        }
        return true
    }
}
