//
//  config.swift
//  SageRollout
//
//  Port of codex-rs/rollout/src/config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `PathBuf` maps to `String`. `SqliteConfig` comes from SageState.
//

import SageState
import Foundation

public protocol RolloutConfigView: Sendable {
    var sageHome: String { get }
    var sqliteConfig: SqliteConfig { get }
    var cwd: String { get }
    var modelProviderId: String { get }
    var generateMemories: Bool { get }
}

public struct RolloutConfig: Equatable, Sendable {
    public var sageHome: String
    public var sqlite: SqliteConfig
    public var cwd: String
    public var modelProviderId: String
    public var generateMemories: Bool

    public init(
        sageHome: String,
        sqlite: SqliteConfig = SqliteConfig(),
        cwd: String = "",
        modelProviderId: String = "",
        generateMemories: Bool = false
    ) {
        self.sageHome = sageHome
        self.sqlite = sqlite
        self.cwd = cwd
        self.modelProviderId = modelProviderId
        self.generateMemories = generateMemories
    }

    public static func fromView(_ view: any RolloutConfigView) -> RolloutConfig {
        RolloutConfig(
            sageHome: view.sageHome,
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
