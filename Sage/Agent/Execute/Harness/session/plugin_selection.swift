//
//  plugin_selection.swift
//  Sage
//
//  Port of codex-rs/core/src/session/plugin_selection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Plugin manager refresh waits for Phase 9.
//

import Foundation

extension Session {
    func activatePluginSelection(_ turnContext: TurnContext) async {
        if state.activeDisabledPluginIds != turnContext.disabledPluginIds {
            state.activeDisabledPluginIds = turnContext.disabledPluginIds
            markMcpRuntimeDirty()
        }
    }
}
