//
//  safety_buffering.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/safety_buffering.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `http::HeaderMap` maps to `[String: String]` (lowercase names).
//

import Foundation

let X_CODEX_SAFETY_BUFFERING_ENABLED_HEADER = "x-codex-safety-buffering-enabled"
let X_CODEX_SAFETY_BUFFERING_FASTER_MODEL_HEADER = "x-codex-safety-buffering-faster-model"

func treatmentFromHeaders(_ headers: [String: String]) -> SafetyBufferingTreatment? {
    let enabled = parseHeaderStr(headers, X_CODEX_SAFETY_BUFFERING_ENABLED_HEADER)
    let faster = parseHeaderStr(headers, X_CODEX_SAFETY_BUFFERING_FASTER_MODEL_HEADER)
    if enabled == nil && faster == nil {
        return nil
    }
    return SafetyBufferingTreatment(fasterModel: faster)
}
