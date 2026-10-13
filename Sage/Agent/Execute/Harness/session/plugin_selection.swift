//
//  plugin_selection.swift
//  Sage
//
//  Port of codex-rs/core/src/session/plugin_selection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Only the disabled-plugin-id sync is live. The plugins manager is
//  frozen product layer (§2.4), so effective plugin hook sources stay
//  empty, `HookSnapshot.matchesPluginHooks` is constant-true, and the
//  hooks refresh branch never fires.
//

import Foundation

extension Session {
    /// rust `Session::activate_plugin_selection`: activate an admitted
    /// task's plugin selection without changing pending settings.
    func activatePluginSelection(_ turnContext: TurnContext) async {
        if state.activeDisabledPluginIds != turnContext.disabledPluginIds {
            state.activeDisabledPluginIds = turnContext.disabledPluginIds
            markMcpRuntimeDirty()
        }
    }
}
