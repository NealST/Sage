//
//  rollout.swift
//  SageCore
//
//  Port of codex-rs/core/src/rollout.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Re-exports the rollout crate. Sage `Config` is not in SageCore, so
//  `RolloutConfigView` is not implemented for it here.
//

import SageHistory
import SageProtocol
import SageRollout
import Foundation

public let SESSIONS_SUBDIR = SageRollout.SESSIONS_SUBDIR
public let ARCHIVED_SESSIONS_SUBDIR = SageRollout.ARCHIVED_SESSIONS_SUBDIR
public let INTERACTIVE_SESSION_SOURCES = SageRollout.INTERACTIVE_SESSION_SOURCES

public typealias RolloutRecorder = SageRollout.RolloutRecorder
public typealias RolloutRecorderParams = SageRollout.RolloutRecorderParams
public typealias RolloutConfig = SageRollout.RolloutConfig
public typealias RolloutConfigView = SageRollout.RolloutConfigView
