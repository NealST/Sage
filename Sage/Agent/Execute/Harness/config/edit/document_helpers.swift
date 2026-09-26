//
//  document_helpers.swift
//  Sage
//
//  Port of codex-rs/core/src/config/edit/document_helpers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  TOML document helpers become dictionary merges for Sage Settings.
//

import Foundation

enum ConfigDocumentHelpers {
    static func merge(_ base: [String: String], overlay: [String: String]) -> [String: String] {
        var merged = base
        for (key, value) in overlay {
            merged[key] = value
        }
        return merged
    }
}
