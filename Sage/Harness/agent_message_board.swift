//
//  agent_message_board.swift
//  SageCore
//
//  Port of codex-rs/core/src/agent_message_board.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `install_agent_message_board` closes over ThreadManager, Config,
//  Feature flags, and the message-board extension crate.
//

import SageProtocol
import Foundation

public func installAgentMessageBoard() throws {
    throw SageErr.unsupportedOperation(
        "install_agent_message_board waits on ThreadManager / Config / AgentMessageBoard extension"
    )
}
