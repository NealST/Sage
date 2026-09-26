//
//  edit.swift
//  Sage
//
//  Port of codex-rs/core/src/config/edit.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Codex TOML document edits become in-memory ConfigOverrides. Sage
//  Settings is the persisted store.
//

import CodexProtocol
import Foundation

enum ConfigEdit: Equatable, Sendable {
    case setModel(String)
    case setApprovalPolicy(CodexProtocol.AskForApproval)
    case enableFeature(Feature)
    case disableFeature(Feature)
}

func applyConfigEdits(_ config: inout Config, _ edits: [ConfigEdit]) {
    for edit in edits {
        switch edit {
        case .setModel(let model):
            config.model = model
        case .setApprovalPolicy(let policy):
            config.approvalPolicy = policy
            config.permissions.approvalPolicy = policy
        case .enableFeature(let feature):
            config.features.enable(feature)
        case .disableFeature(let feature):
            config.features.enabledFeatures.remove(feature)
        }
    }
}
