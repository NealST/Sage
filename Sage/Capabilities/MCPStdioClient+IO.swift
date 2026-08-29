//
//  MCPStdioClient+IO.swift
//  Sage
//

import Foundation

extension MCPStdioClient {
    // MARK: - Process I/O

    func startProcess() throws {
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

        let invocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [config.command] + config.args,
            configuration: .mcpServer(
                writableRoots: writableRoots,
                allowsProtectedMetadataWrites: allowsProtectedMetadataWrites
            ),
            auditComponent: "mcp_server"
        )
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        process.environment = ChildProcessEnvironment.sanitized(overrides: config.env)

        try process.run()
        ProcessRunner.registerExternal(process)
        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        startStdoutReader(stdout.fileHandleForReading)
        startStderrReader(stderr.fileHandleForReading)
    }

    func startStdoutReader(_ handle: FileHandle) {
        let serverID = config.id
        let stdoutStream = Self.asyncDataStream(from: handle)
        readTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in stdoutStream {
                guard !Task.isCancelled else { break }
                await self.consume(chunk)
            }
            let shouldNotify = await !self.isDisconnecting
            if shouldNotify {
                let didClean = await self.forceCleanup()
                if didClean, let callback = await self.onProcessExit {
                    await callback(serverID)
                }
            }
        }
    }

    func startStderrReader(_ handle: FileHandle) {
        let stderrStream = Self.asyncDataStream(from: handle)
        stderrTask = Task { [weak self] in
            guard let self else { return }
            var stderrBuffer = Data()
            for await chunk in stderrStream {
                guard !Task.isCancelled else { break }
                stderrBuffer.append(chunk)
                stderrBuffer = await self.drainStderrLines(stderrBuffer)
            }
            await self.flushStderrRemainder(stderrBuffer)
        }
    }

    func drainStderrLines(_ buffer: Data) -> Data {
        var remaining = buffer
        while let range = remaining.range(of: Data([0x0A])) {
            let lineData = remaining.subdata(in: remaining.startIndex..<range.lowerBound)
            remaining.removeSubrange(remaining.startIndex...range.lowerBound)
            if let text = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                appendStderrLine(text)
            }
        }
        return remaining
    }

    func flushStderrRemainder(_ buffer: Data) {
        guard !buffer.isEmpty,
              let text = String(data: buffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        appendStderrLine(text)
    }

    func appendStderrLine(_ line: String) {
        recentStderrLines.append(line)
        if recentStderrLines.count > Self.stderrLineLimit {
            recentStderrLines.removeFirst(recentStderrLines.count - Self.stderrLineLimit)
        }
    }

    /// Creates an AsyncStream that reads from a FileHandle on a dedicated thread,
    /// avoiding blocking the Swift concurrency cooperative thread pool.
    static func asyncDataStream(from handle: FileHandle) -> AsyncStream<Data> {
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

    func startHealthCheck() {
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

    func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let range = buffer.range(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            handleLine(line)
        }
    }

    func handleLine(_ line: Data) {
        guard !line.isEmpty,
              let obj = try? JSONDecoder().decode(JSONValue.self, from: line),
              case .object(let map) = obj
        else { return }

        if let idValue = map["id"] {
            let id: Int?
            if case .number(let number) = idValue {
                id = Int(number)
            } else if case .string(let string) = idValue {
                id = Int(string)
            } else {
                id = nil
            }
            guard let id, let cont = pending.removeValue(forKey: id) else { return }
            if let error = map["error"] {
                cont.resume(throwing: ClientError.remote(stringify(error)))
            } else {
                cont.resume(returning: map["result"] ?? .null)
            }
        }
    }

    func request(method: String, params: JSONValue) async throws -> JSONValue {
        guard let stdinPipe else { throw ClientError.notRunning }
        let id = nextID
        nextID += 1

        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params,
        ])

        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                if Task.isCancelled {
                    cont.resume(throwing: CancellationError())
                    return
                }
                pending[id] = cont
                do {
                    try write(payload, to: stdinPipe)
                } catch {
                    pending.removeValue(forKey: id)
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelPendingRequest(id: id) }
        }
    }

    private func cancelPendingRequest(id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    func notify(method: String, params: JSONValue) throws {
        guard let stdinPipe else { throw ClientError.notRunning }
        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params,
        ])
        try write(payload, to: stdinPipe)
    }

    func write(_ value: JSONValue, to pipe: Pipe) throws {
        let data = try JSONEncoder().encode(value)
        var line = data
        line.append(0x0A)
        try pipe.fileHandleForWriting.write(contentsOf: line)
    }

    // MARK: - Parsing

    func parseTools(_ result: JSONValue) -> [MCPToolInfo] {
        guard case .object(let root) = result,
              case .array(let tools) = root["tools"]
        else { return [] }

        return tools.compactMap { item in
            guard case .object(let tool) = item,
                  case .string(let name) = tool["name"]
            else { return nil }
            let description: String
            if case .string(let text) = tool["description"] {
                description = text
            } else {
                description = name
            }
            let schema = tool["inputSchema"] ?? .object(["type": .string("object"), "properties": .object([:])])
            let annotations: [String: JSONValue]
            if case .object(let values) = tool["annotations"] {
                annotations = values
            } else {
                annotations = [:]
            }
            let readOnlyHint: Bool?
            if case .bool(let value) = annotations["readOnlyHint"] {
                readOnlyHint = value
            } else {
                readOnlyHint = nil
            }
            let localWriteHint: Bool
            if case .bool(let value) = annotations["localWriteHint"] {
                localWriteHint = value
            } else {
                localWriteHint = false
            }
            return MCPToolInfo(
                serverID: config.id,
                serverName: config.name,
                name: name,
                description: description,
                inputSchema: schema,
                readOnlyHint: readOnlyHint,
                localWriteHint: localWriteHint,
                serverAuthorizationFingerprint: config.authorizationFingerprint
            )
        }
    }

    func stringify(_ value: JSONValue) -> String {
        if case .string(let string) = value { return string }
        if let data = try? JSONEncoder().encode(value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(value)"
    }
}
