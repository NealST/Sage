//
//  windows_sandbox_config.swift
//  Sage
//
//  Port of codex-rs/core/src/config/windows_sandbox_config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Windows sandbox is out of scope on macOS. The type exists for Config.
//

import CodexProtocol
import Foundation

struct WindowsSandboxConfig: Equatable, Sendable {
    var level: WindowsSandboxLevel

    init(level: WindowsSandboxLevel = .disabled) {
        self.level = level
    }
}
