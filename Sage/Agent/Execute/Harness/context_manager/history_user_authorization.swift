//
//  history_user_authorization.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context_manager/history_user_authorization.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public func userAuthorizationItems(_ items: [ResponseItem]) -> [ResponseItem] {
    items.filter(isUserAuthorizationMessage)
}
