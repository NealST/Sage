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
    private let config: MCPServerConfig
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextID: Int = 1
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var readTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?

    /// Ring buffer of recent stderr lines (max `stderrLineLimit`).
    private(set) var recentStderrLines: [String] = []
    private static let stderrLineLimit = 50

    /// Called when the server process exits unexpectedly (not via `disconnect`).
    /// The callback receives the server config ID.
    var onProcessExit: (@Sendable (String) async -> Void)?

    /// True while a graceful disconnect is in progress — suppresses exit callback.
    private var isDisconnecting = false

    /// Parent-process keys MCP children may inherit. API keys and other secrets stay out.
    nonisolated private static let inheritedEnvironmentKeys: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "SHELL",
        "TMPDIR", "TMP", "TEMP",
        "LANG", "LC_ALL", "LC_CTYPE",
        "SSH_AUTH_SOCK",
    ]

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

    init(config: MCPServerConfig) {
        self.config = config
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
    private var didCleanup = false

    /// Immediate teardown without graceful shutdown (used internally after crash detection).
    /// Returns `true` if this call actually performed cleanup (first call wins).
    @discardableResult
    private func forceCleanup() -> Bool {
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
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        buffer = Data()
        return true
    }

    /// Returns the most recent stderr lines for display.
    var stderrLog: [String] { recentStderrLines }

    // MARK: - Process I/O

    private func startProcess() throws {
        // Reset state for a fresh connection.
        // Note: the caller (CapabilityStore.connect) already disconnects the old client,
        // so we only need to ensure local state is clean.
        forceCleanup()
        didCleanup = false
        recentStderrLines = []

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [config.command] + config.args
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        var environment: [String: String] = [:]
        let parent = ProcessInfo.processInfo.environment
        for key in Self.inheritedEnvironmentKeys {
            if let value = parent[key] {
                environment[key] = value
            }
        }
        for (key, value) in config.env {
            environment[key] = value
        }
        process.environment = environment

        try process.run()
        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        let serverID = config.id

        // stdout reader — JSON-RPC responses.
        // availableData blocks the calling thread, so read on a dedicated non-cooperative
        // thread via AsyncStream to avoid starving the Swift concurrency thread pool.
        let stdoutStream = Self.asyncDataStream(from: stdout.fileHandleForReading)
        readTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in stdoutStream {
                guard !Task.isCancelled else { break }
                await self.consume(chunk)
            }
            // Stream ended (EOF / process exited) — notify coordinator if not graceful.
            let shouldNotify = await !self.isDisconnecting
            if shouldNotify {
                let didClean = await self.forceCleanup()
                if didClean, let callback = await self.onProcessExit {
                    await callback(serverID)
                }
            }
        }

        // stderr reader — log capture (same non-blocking pattern).
        let stderrStream = Self.asyncDataStream(from: stderr.fileHandleForReading)
        stderrTask = Task { [weak self] in
            guard let self else { return }
            var stderrBuffer = Data()
            for await chunk in stderrStream {
                guard !Task.isCancelled else { break }
                stderrBuffer.append(chunk)
                while let range = stderrBuffer.range(of: Data([0x0A])) {
                    let lineData = stderrBuffer.subdata(in: stderrBuffer.startIndex..<range.lowerBound)
                    stderrBuffer.removeSubrange(stderrBuffer.startIndex...range.lowerBound)
                    if let text = String(data: lineData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        await self.appendStderrLine(text)
                    }
                }
            }
            // Flush remaining partial line
            if !stderrBuffer.isEmpty,
               let text = String(data: stderrBuffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                await self.appendStderrLine(text)
            }
        }
    }

    private func appendStderrLine(_ line: String) {
        recentStderrLines.append(line)
        if recentStderrLines.count > Self.stderrLineLimit {
            recentStderrLines.removeFirst(recentStderrLines.count - Self.stderrLineLimit)
        }
    }

    /// Creates an AsyncStream that reads from a FileHandle on a dedicated thread,
    /// avoiding blocking the Swift concurrency cooperative thread pool.
    private static func asyncDataStream(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            // `Thread` is not Sendable; box it so `onTermination` can cancel safely.
            final class ReaderThread: @unchecked Sendable {
                private let lock = NSLock()
                private var thread: Thread?

                func start(_ body: @escaping @Sendable () -> Void) {
                    let thread = Thread(block: body)
                    thread.qualityOfService = .userInitiated
                    lock.lock()
                    self.thread = thread
                    lock.unlock()
                    thread.start()
                }

                func cancel() {
                    lock.lock()
                    let thread = thread
                    self.thread = nil
                    lock.unlock()
                    thread?.cancel()
                }
            }

            let reader = ReaderThread()
            reader.start {
                while !Thread.current.isCancelled {
                    let data = handle.availableData
                    if data.isEmpty {
                        // EOF — pipe closed or process exited.
                        continuation.finish()
                        return
                    }
                    continuation.yield(data)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                reader.cancel()
            }
        }
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        healthTask?.cancel()
        let serverID = config.id
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                do {
                    _ = try await withThrowingTaskGroup(of: JSONValue.self) { group in
                        group.addTask { [self] in
                            try await self.request(method: "ping", params: .object([:]))
                        }
                        group.addTask {
                            try await Task.sleep(for: .seconds(5))
                            throw ClientError.pingTimeout
                        }
                        guard let result = try await group.next() else {
                            throw CancellationError()
                        }
                        group.cancelAll()
                        return result
                    }
                } catch {
                    // Ping failed or timed out — treat as unresponsive.
                    guard !Task.isCancelled else { break }
                    let didClean = await self.forceCleanup()
                    if didClean, let callback = await self.onProcessExit {
                        await callback(serverID)
                    }
                    break
                }
            }
        }
    }

    // MARK: - JSON-RPC Framing

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let range = buffer.range(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        guard !line.isEmpty,
              let obj = try? JSONDecoder().decode(JSONValue.self, from: line),
              case .object(let map) = obj
        else { return }

        if let idValue = map["id"] {
            let id: Int?
            if case .number(let n) = idValue { id = Int(n) }
            else if case .string(let s) = idValue { id = Int(s) }
            else { id = nil }
            guard let id, let cont = pending.removeValue(forKey: id) else { return }
            if let error = map["error"] {
                cont.resume(throwing: ClientError.remote(stringify(error)))
            } else {
                cont.resume(returning: map["result"] ?? .null)
            }
        }
    }

    private func request(method: String, params: JSONValue) async throws -> JSONValue {
        guard let stdinPipe else { throw ClientError.notRunning }
        let id = nextID
        nextID += 1

        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params,
        ])

        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            do {
                try write(payload, to: stdinPipe)
            } catch {
                pending.removeValue(forKey: id)
                cont.resume(throwing: error)
            }
        }
    }

    private func notify(method: String, params: JSONValue) throws {
        guard let stdinPipe else { throw ClientError.notRunning }
        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params,
        ])
        try write(payload, to: stdinPipe)
    }

    private func write(_ value: JSONValue, to pipe: Pipe) throws {
        let data = try JSONEncoder().encode(value)
        var line = data
        line.append(0x0A)
        try pipe.fileHandleForWriting.write(contentsOf: line)
    }

    // MARK: - Parsing

    private func parseTools(_ result: JSONValue) -> [MCPToolInfo] {
        guard case .object(let root) = result,
              case .array(let tools) = root["tools"]
        else { return [] }

        return tools.compactMap { item in
            guard case .object(let tool) = item,
                  case .string(let name) = tool["name"]
            else { return nil }
            let description: String
            if case .string(let d) = tool["description"] {
                description = d
            } else {
                description = name
            }
            let schema = tool["inputSchema"] ?? .object(["type": .string("object"), "properties": .object([:])])
            return MCPToolInfo(
                serverID: config.id,
                serverName: config.name,
                name: name,
                description: description,
                inputSchema: schema
            )
        }
    }

    private func stringify(_ value: JSONValue) -> String {
        if case .string(let s) = value { return s }
        if let data = try? JSONEncoder().encode(value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(value)"
    }
}
