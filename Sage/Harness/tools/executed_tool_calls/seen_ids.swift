//
//  seen_ids.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/executed_tool_calls/seen_ids.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

struct SeenIds {
    private var ids: Set<String> = []

    mutating func insert(_ id: String) -> Bool {
        ids.insert(id).inserted
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }
}
