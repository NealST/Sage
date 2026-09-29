//
//  cyber_access_program.swift
//  CodexCore
//
//  Port of codex-rs/core/src/cyber_access_program.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `CodexAuth` is not in CodexCore. The ChatGPT-auth gate is expressed as
//  a boolean so callers can supply it once login is ported.
//

import CodexAPI
import CodexProtocol
import Foundation

public func forAuth(
    isChatgptAuth: Bool,
    program: CyberAccessProgram?
) -> AccessPrograms? {
    guard isChatgptAuth, let program else { return nil }
    return AccessPrograms(program)
}
