//
//  lib.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Same-module types are already visible; no re-export surface is required.
//  Local JSONL store (`local/`) is a working create/resume/append/read/list/delete
//  subset. `migrateRollouts` dry-run is ported; Apply / GRDB query paths throw.
//

import Foundation
