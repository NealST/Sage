//
//  child.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/child.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Local child with wait/kill. Tokio Child is replaced by NativeChild.
//

import Foundation

public final class Child: @unchecked Sendable {
    var native: NativeChild
    public var stdin: FileHandle?
    public var stdout: FileHandle?
    public var stderr: FileHandle?

    init(native: NativeChild, stdin: FileHandle?, stdout: FileHandle?, stderr: FileHandle?) {
        self.native = native
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
    }

    public func id() -> UInt32? { native.id() }

    public func wait() async throws -> Int32 {
        stdin = nil
        return try await native.wait()
    }

    public func waitWithOutput() async throws -> (status: Int32, stdout: Data, stderr: Data) {
        let outHandle = stdout
        let errHandle = stderr
        stdout = nil
        stderr = nil
        async let status = wait()
        async let out = Task { outHandle?.readDataToEndOfFile() ?? Data() }.value
        async let err = Task { errHandle?.readDataToEndOfFile() ?? Data() }.value
        return try await (status, out, err)
    }

    public func kill() async throws {
        stdin = nil
        try await native.kill()
    }
}
