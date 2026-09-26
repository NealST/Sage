//
//  error.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/error.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public enum ThreadStoreError: Error, Equatable, Sendable {
    case unsupported(operation: String)
    case conflict(message: String)
    case threadNotFound(String)
    case invalidRequest(String)
    case `internal`(String)
}

public typealias ThreadStoreResult<T> = Result<T, ThreadStoreError>

func rejectPaginatedHistoryMode(_ historyMode: ThreadHistoryMode) throws {
    if historyMode == .paginated {
        throw ThreadStoreError.unsupported(operation: "paginated_threads")
    }
}
