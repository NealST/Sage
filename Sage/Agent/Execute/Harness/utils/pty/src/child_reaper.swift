//
//  child_reaper.swift
//  CodexUtils
//
//  Sage addition (no codex counterpart).
//
//  Background waitpid worker kept after upstream folded reaping into
//  macos_child.rs. Sage owns NativeChild PIDs directly.
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
