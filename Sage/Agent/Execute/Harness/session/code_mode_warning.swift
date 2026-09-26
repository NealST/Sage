//
//  code_mode_warning.swift
//  Sage
//
//  Port of codex-rs/core/src/session/code_mode_warning.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

func unsupportedCodeModeWarning(modelSlug: String, features: Features, advertisesCodeMode: Bool) -> String? {
    let enabled = features.enabled(.codeMode) || features.enabled(.codeModeOnly)
    guard enabled, !advertisesCodeMode else { return nil }
    return "Code Mode is enabled in configuration, but model `\(modelSlug)` does not advertise Code Mode support. This may degrade model performance. Disable `features.code_mode` and `features.code_mode_only`, or select a model whose metadata enables Code Mode."
}
