//
//  lib.swift
//  CodexState
//
//  Port of codex-rs/state/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Lives under `state/src/` so Harness/state/ (Phase 5 session services)
//  stays in the Sage app synchronized group. Xcode excludes this `src/`
//  folder from the app target.
//

import CodexProtocol
import Foundation

/// Identifies internal review threads whose user messages are synthetic approval prompts.
public let GUARDIAN_THREAD_TITLE = "Guardian review"
public let GUARDIAN_THREAD_PREVIEW = "Approval review"

public func isGuardianReviewSource(_ source: SessionSource) -> Bool {
    if case .subAgent(.other(let name)) = source {
        return name == "guardian"
    }
    return false
}

/// Maximum number of pending user submissions permitted for one thread.
public let MAX_QUEUE_ITEMS = 100

/// Maximum serialized size of one persisted thread-attachment payload.
public let MAX_THREAD_ATTACHMENT_PAYLOAD_BYTES = 64 * 1024

/// Maximum byte length of a persisted attachment type.
public let MAX_THREAD_ATTACHMENT_TYPE_BYTES = 256

/// Maximum byte length of a persisted stable attachment identity key.
public let MAX_THREAD_ATTACHMENT_IDENTITY_KEY_BYTES = 256

/// Maximum number of attachments returned in one page.
public let MAX_THREAD_ATTACHMENT_LIST_PAGE_SIZE = 100

/// Maximum number of active attachments retained for one thread.
public let MAX_THREAD_ATTACHMENTS_PER_THREAD = 100

/// Stable UUIDv7 identifying the built-in pinned thread section.
public let PINNED_THREAD_SECTION_ID = "01984de2-8f74-7c91-a3b2-5c5e937cf318"

/// User-facing name of the built-in pinned thread section.
public let PINNED_THREAD_SECTION_NAME = "Pinned"

/// Environment variable for overriding the SQLite state database home directory.
public let SQLITE_HOME_ENV = "CODEX_SQLITE_HOME"
