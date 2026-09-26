//
//  pty_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Public spawn aliases and the 1 MiB output cap. Linux spawn-helper and
//  Windows ConPTY backends are excluded(platform). Tokio channels map to
//  AsyncStream / Task.
//

public let DEFAULT_OUTPUT_BYTES_CAP = 1024 * 1024

public typealias ExecCommandSession = ProcessHandle
public typealias SpawnedPty = SpawnedProcess
