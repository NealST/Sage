//
//  child_reaper.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/child_reaper.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Background waitpid worker. Tokio-child transfer is not needed because
//  Sage owns NativeChild PIDs directly.
//

import Darwin
import Foundation

enum ChildToReap {
    case pid(pid_t)
}

enum ChildReaper {
    private static let queue = DispatchQueue(label: "codex.pty.reaper")

    static func reap(_ pid: pid_t) {
        queue.async {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        }
    }
}
