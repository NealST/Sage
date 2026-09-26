//
//  managed_features.swift
//  Sage
//
//  Port of codex-rs/core/src/config/managed_features.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

enum Feature: String, Equatable, Hashable, Sendable {
    case codeMode = "code_mode"
    case codeModeOnly = "code_mode_only"
    case currentTimeReminder = "current_time_reminder"
    case webSearchRequest = "web_search_request"
    case webSearchCached = "web_search_cached"
    case unifiedExec = "unified_exec"
    case unboundedConnectionRetries = "unbounded_connection_retries"
    case unifiedImageBudget = "unified_image_budget"
}

struct Features: Equatable, Sendable {
    var enabledFeatures: Set<Feature>

    init(_ enabled: Set<Feature> = []) {
        self.enabledFeatures = enabled
    }

    func enabled(_ feature: Feature) -> Bool {
        enabledFeatures.contains(feature)
    }

    mutating func enable(_ feature: Feature) {
        enabledFeatures.insert(feature)
    }
}

typealias ManagedFeatures = Features
