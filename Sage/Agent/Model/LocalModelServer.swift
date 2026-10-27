//
//  LocalModelServer.swift
//  Sage
//
//  In-process OpenAI-compatible server on the loopback interface. Local
//  model selections route here by swapping the snapshot's baseURL, so the
//  existing cloud request path (ModelClient, harness, probe, retries)
//  serves local models unchanged.
//
//  This file holds the thread-safe endpoint holder and startup entry point;
//  HTTP wiring lives in LocalModelServer+HTTP.swift.
//

import Foundation

final class LocalModelServer: @unchecked Sendable {
    static let shared = LocalModelServer()

    private let stateLock = NSLock()
    private var _endpointBaseURL: URL?
    private var startTask: Task<Void, Never>?
    private var _lastError: String?

    /// `http://127.0.0.1:<port>/v1` once the server is up, else `nil`.
    var endpointBaseURL: URL? {
        stateLock.withLock { _endpointBaseURL }
    }

    /// Startup failure surfaced for diagnostics; `nil` while running.
    var lastError: String? {
        stateLock.withLock { _lastError }
    }

    /// Snapshot routing target. Before the server has started, returns a
    /// guaranteed-dead URL so requests fail fast with an obvious error
    /// instead of silently hitting some other local service.
    var baseURLString: String {
        if let endpointBaseURL {
            return endpointBaseURL.absoluteString
        }
        return Self.unavailableBaseURLString
    }

    static let unavailableBaseURLString = "http://127.0.0.1:1/v1"

    private init() {}

    func setEndpoint(_ url: URL?) {
        stateLock.withLock { _endpointBaseURL = url }
    }

    func noteServerError(_ message: String) {
        stateLock.withLock { _lastError = message }
    }

    /// Launches the server once on a background task. Safe to call from
    /// anywhere (app start, tests) — subsequent calls are no-ops.
    func start() {
        stateLock.withLock {
            guard startTask == nil else { return }
            startTask = Task.detached(priority: .utility) { [self] in
                await runServer()
            }
        }
    }
}
