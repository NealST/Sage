//
//  turn_diff_tracker.swift
//  CodexCore
//
//  Port of codex-rs/core/src/turn_diff_tracker.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct TurnDiffTracker: Equatable, Sendable {
    public var unifiedDiff: String
    public var changedPaths: [String]

    public init(unifiedDiff: String = "", changedPaths: [String] = []) {
        self.unifiedDiff = unifiedDiff
        self.changedPaths = changedPaths
    }

    public mutating func record(path: String, diff: String) {
        changedPaths.append(path)
        if unifiedDiff.isEmpty {
            unifiedDiff = diff
        } else {
            unifiedDiff += "\n" + diff
        }
    }
}
