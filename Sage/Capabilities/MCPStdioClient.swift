//
//  MCPStdioClient.swift
//  Sage
//

import Foundation

/// MCP JSON-RPC client over stdio with health monitoring.
///
/// Responsibilities (transport layer only):
/// - Process lifecycle: start, graceful shutdown, force kill
/// - JSON-RPC framing: initialize, tools/list, tools/call, ping
/// - stderr capture: ring buffer of recent log lines
/// - Process exit detection: notifies the coordinator via callback
///
/// Reconnection logic lives in `CapabilityStore` (coordination layer).
actor MCPStdioClient {
    let config: MCPServerConfig
    let writableRoots: [URL]
    let allowsProtectedMetadataWrites: Bool
    var process: Process?
    var stdinPipe: Pipe?
    var stdoutPipe: Pipe?
    var nextID: Int = 1
    var buffer = Data()
    var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    var readTask: Task<Void, Never>?
    var stderrTask: Task<Void, Never>?
    var healthTask: Task<Void, Never>?

    /// Ring buffer of recent stderr lines (max `stderrLineLimit`).
    var recentStderrLines: [String] = []
    static let stderrLineLimit = 50

    /// Called when the server process exits unexpectedly (not via `disconnect`).
    /// The callback receives the server config ID.
    var onProcessExit: (@Sendable (String) async -> Void)?

    /// True while a graceful disconnect is in progress — suppresses exit callback.
    var isDisconnecting = false

    init(
        config: MCPServerConfig,
        writableRoots: [URL] = [],
        allowsProtectedMetadataWrites: Bool = false
    ) {
        self.config = config
        self.writableRoots = writableRoots
        self.allowsProtectedMetadataWrites = allowsProtectedMetadataWrites
    }

    enum ClientError: LocalizedError {
        case notRunning
        case invalidResponse(String)
        case remote(String)
        case pingTimeout

        var errorDescription: String? {
            switch self {
            case .notRunning: return "MCP server is not running"
            case .invalidResponse(let detail): return "Invalid MCP response: \(detail)"
            case .remote(let detail): return detail
            case .pingTimeout: return "MCP server did not respond to ping"
            }
        }
    }

    func setOnProcessExit(_ callback: @escaping @Sendable (String) async -> Void) {
        onProcessExit = callback
    }

    // MARK: - Public API

    func connect() async throws -> [MCPToolInfo] {
        try startProcess()
        _ = try await request(
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("Sage"),
                    "version": .string("1.0"),
                ]),
            ])
        )
        try notify(method: "notifications/initialized", params: .object([:]))
        let listed = try await request(method: "tools/list", params: .object([:]))
        let tools = parseTools(listed)
        startHealthCheck()
        return tools
    }

    func callTool(name: String, argumentsJSON: String) async throws -> String {
        let argsValue: JSONValue
        if let data = argumentsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            argsValue = decoded
        } else {
            argsValue = .object([:])
        }

        let result = try await request(
            method: "tools/call",
            params: .object([
                "name": .string(name),
                "arguments": argsValue,
            ])
        )
        return stringify(result)
    }

    /// Graceful shutdown: send `shutdown` RPC, wait up to 3s, then force terminate.
    func disconnect() async {
        isDisconnecting = true
        healthTask?.cancel()
        healthTask = nil

        // Attempt graceful shutdown if the process is still running.
        if stdinPipe != nil, process?.isRunning == true {
            do {
                _ = try await withThrowingTaskGroup(of: JSONValue.self) { group in
                    group.addTask { [self] in
                        try await self.request(method: "shutdown", params: .object([:]))
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(3))
                        throw ClientError.pingTimeout
                    }
                    guard let result = try await group.next() else {
                        throw CancellationError()
                    }
                    group.cancelAll()
                    return result
                }
            } catch {
                // Shutdown request failed or timed out — proceed to force kill.
            }
        }

        forceCleanup()
        isDisconnecting = false
        didCleanup = false
    }

    /// True once forceCleanup has fired — prevents double exit notification.
    var didCleanup = false

    /// Immediate teardown without graceful shutdown (used internally after crash detection).
    /// Returns `true` if this call actually performed cleanup (first call wins).
    @discardableResult
    func forceCleanup() -> Bool {
        guard !didCleanup else { return false }
        didCleanup = true
        readTask?.cancel()
        readTask = nil
        stderrTask?.cancel()
        stderrTask = nil
        healthTask?.cancel()
        healthTask = nil
        for (_, cont) in pending {
            cont.resume(throwing: ClientError.notRunning)
        }
        pending.removeAll()
        if let process {
            ProcessRunner.unregisterExternal(process)
            if process.isRunning {
                ProcessRunner.terminateExternal(process)
            }
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        buffer = Data()
        return true
    }

    /// Returns the most recent stderr lines for display.
    var stderrLog: [String] { recentStderrLines }
}
