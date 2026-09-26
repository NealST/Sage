//
//  rollout.swift
//  CodexCore
//
//  Port of codex-rs/core/src/rollout.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Re-exports the rollout crate. Sage `Config` is not in CodexCore, so
//  `RolloutConfigView` is not implemented for it here.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

public let SESSIONS_SUBDIR = CodexRollout.SESSIONS_SUBDIR
public let ARCHIVED_SESSIONS_SUBDIR = CodexRollout.ARCHIVED_SESSIONS_SUBDIR
public let INTERACTIVE_SESSION_SOURCES = CodexRollout.INTERACTIVE_SESSION_SOURCES

public typealias RolloutRecorder = CodexRollout.RolloutRecorder
public typealias RolloutRecorderParams = CodexRollout.RolloutRecorderParams
public typealias RolloutConfig = CodexRollout.RolloutConfig
public typealias RolloutConfigView = CodexRollout.RolloutConfigView
