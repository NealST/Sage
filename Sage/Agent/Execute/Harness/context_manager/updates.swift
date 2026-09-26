//
//  updates.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context_manager/updates.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct ContextManagerUpdates: Equatable, Sendable {
    public var items: [ResponseItem]
    public var referenceContextItem: TurnContextItem?

    public init(items: [ResponseItem] = [], referenceContextItem: TurnContextItem? = nil) {
        self.items = items
        self.referenceContextItem = referenceContextItem
    }
}
