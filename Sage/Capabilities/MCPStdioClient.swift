//
//  MCPStdioClient.swift
//  Sage
//

import Foundation

/// Minimal MCP JSON-RPC client over stdio (initialize + tools/list + tools/call).
actor MCPStdioClient {
    private let config: MCPServerConfig
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextID: Int = 1
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var readTask: Task<Void, Never>?

    enum ClientError: LocalizedError {
        case notRunning
        case invalidResponse(String)
        case remote(String)

        var errorDescription: String? {
            switch self {
            case .notRunning: return "MCP server is not running"
            case .invalidResponse(let detail): return "Invalid MCP response: \(detail)"
            case .remote(let detail): return detail
            }
        }
    }

    init(config: MCPServerConfig) {
        self.config = config
    }

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
        try await notify(method: "notifications/initialized", params: .object([:]))
        let listed = try await request(method: "tools/list", params: .object([:]))
        let tools = parseTools(listed)
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

    func disconnect() {
        readTask?.cancel()
        readTask = nil
        for (_, cont) in pending {
            cont.resume(throwing: ClientError.notRunning)
        }
        pending.removeAll()
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        buffer = Data()
    }

    // MARK: - Process I/O

    private func startProcess() throws {
        disconnect()

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [config.command] + config.args
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in config.env {
            environment[key] = value
        }
        process.environment = environment

        try process.run()
        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        readTask = Task { [weak self] in
            guard let self else { return }
            let handle = stdout.fileHandleForReading
            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    try? await Task.sleep(for: .milliseconds(40))
                    if process.isRunning == false { break }
                    continue
                }
                await self.consume(chunk)
            }
        }
    }

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

    private func notify(method: String, params: JSONValue) async throws {
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
