//
//  model_context.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/model_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexHistory
import Foundation

/// Whether a reverse model-context scan needs more rollout items.
public enum ModelContextScanProgress: Equatable, Sendable {
    /// The reader should provide the next older rollout item.
    case `continue`
    /// The scan has collected a safe bounded suffix.
    case complete
}

/// Finds a bounded suffix for reconstructing the most recent context window.
///
/// A compaction with replacement history and a window number is a complete conversation-history
/// boundary. Records after it provide any companion state that was persisted. Older compactions
/// missing either field require the complete rollout so reconstruction can rebuild their history
/// or window number.
public struct ModelContextScan {
    private var itemsNewestFirst: [RolloutItem] = []
    private var requiresFullReplay = false

    public init() {}

    /// Adds the next newest-to-oldest rollout item and reports whether the reader can stop.
    public mutating func push(_ item: RolloutItem) -> ModelContextScanProgress {
        let progress: ModelContextScanProgress
        if requiresFullReplay {
            progress = .continue
        } else if case .compacted(let compacted) = item {
            if compacted.replacementHistory != nil && compacted.windowNumber != nil {
                progress = .complete
            } else {
                // This compaction cannot be reconstructed from a bounded suffix. Do not stop at
                // an older compaction because this newer one still affects the surviving history.
                requiresFullReplay = true
                progress = .continue
            }
        } else {
            progress = .continue
        }
        itemsNewestFirst.append(item)
        return progress
    }

    /// Returns the collected items in chronological order.
    ///
    /// Call this after the reader reaches the beginning of its source or after `push`
    /// returns `ModelContextScanProgress.complete`.
    public func finish() -> [RolloutItem] {
        Array(itemsNewestFirst.reversed())
    }
}
