//
//  additional_context.swift
//  Sage
//
//  Port of codex-rs/core/src/state/additional_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexCore
import CodexProtocol
import Foundation

struct AdditionalContextStore: Equatable, Sendable {
    var values: [String: AdditionalContextEntry] = [:]

    init() {}

    mutating func merge(_ values: [String: AdditionalContextEntry]) -> [ResponseItem] {
        var fragments: [ResponseItem] = []
        for (key, entry) in values where self.values[key] != entry {
            switch entry.kind {
            case .untrusted:
                fragments.append(AdditionalContextUserFragment(key: key, value: entry.value).asResponseItem())
            case .application:
                fragments.append(AdditionalContextDeveloperFragment(key: key, value: entry.value).asResponseItem())
            }
        }
        self.values = values
        return fragments
    }
}
