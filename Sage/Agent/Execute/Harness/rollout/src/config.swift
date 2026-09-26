//
//  config.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `PathBuf` maps to `String`. `SqliteConfig` comes from CodexState.
//

import CodexState
import Foundation

public protocol RolloutConfigView: Sendable {
    var codexHome: String { get }
    var sqliteConfig: SqliteConfig { get }
    var cwd: String { get }
    var modelProviderId: String { get }
    var generateMemories: Bool { get }
}

public struct RolloutConfig: Equatable, Sendable {
    public var codexHome: String
    public var sqlite: SqliteConfig
    public var cwd: String
    public var modelProviderId: String
    public var generateMemories: Bool

    public init(
        codexHome: String,
        sqlite: SqliteConfig = SqliteConfig(),
        cwd: String = "",
        modelProviderId: String = "",
        generateMemories: Bool = false
    ) {
        self.codexHome = codexHome
        self.sqlite = sqlite
        self.cwd = cwd
        self.modelProviderId = modelProviderId
        self.generateMemories = generateMemories
    }

    public static func fromView(_ view: any RolloutConfigView) -> RolloutConfig {
        RolloutConfig(
            codexHome: view.codexHome,
            sqlite: view.sqliteConfig,
            cwd: view.cwd,
            modelProviderId: view.modelProviderId,
            generateMemories: view.generateMemories
        )
    }
}

public typealias Config = RolloutConfig

extension RolloutConfig: RolloutConfigView {
    public var sqliteConfig: SqliteConfig { sqlite }
}
