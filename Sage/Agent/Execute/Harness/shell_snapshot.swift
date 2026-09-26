//
//  shell_snapshot.swift
//  Sage
//
//  Port of codex-rs/core/src/shell_snapshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  StateDb, session telemetry, exec-server Environment, and credential-
//  broker restore wait for Phase 4–5. Capture writes a login-shell
//  `export -p` snapshot through ShellSnapshotSandbox when provided, or a
//  local Process otherwise.
//

import CodexProtocol
import CodexSandboxing
import CodexShellCommand
import CodexUtils
import Foundation

let SNAPSHOT_TIMEOUT: Duration = .seconds(10)
let SNAPSHOT_RETENTION_SECONDS: TimeInterval = 60 * 60 * 24 * 3
let SNAPSHOT_DIR = "shell_snapshots"

enum SnapshotCredentialBrokerState: Equatable, Sendable {
    case starting
    case inactive
    case unavailable
    case ready(NetworkProxy)
}

final class SnapshotCredentialBrokerChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var state: SnapshotCredentialBrokerState

    init(_ state: SnapshotCredentialBrokerState = .starting) {
        self.state = state
    }

    func sendReplace(_ next: SnapshotCredentialBrokerState) -> SnapshotCredentialBrokerState {
        lock.lock()
        let previous = state
        state = next
        lock.unlock()
        return previous
    }

    func current() -> SnapshotCredentialBrokerState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}

struct ShellSnapshotConfig {
    var codexHome: AbsolutePathBuf
    var sessionId: ThreadId
    var preferExecutorSnapshots: Bool
}

struct ShellSnapshot {
    var config: ShellSnapshotConfig?
    var credentialBroker: SnapshotCredentialBrokerChannel?

    init(
        codexHome: AbsolutePathBuf,
        sessionId: ThreadId,
        credentialBroker: SnapshotCredentialBrokerChannel? = nil,
        preferExecutorSnapshots: Bool = false
    ) {
        self.config = ShellSnapshotConfig(
            codexHome: codexHome,
            sessionId: sessionId,
            preferExecutorSnapshots: preferExecutorSnapshots
        )
        self.credentialBroker = credentialBroker
    }

    static func disabled() -> ShellSnapshot {
        ShellSnapshot(config: nil, credentialBroker: nil)
    }

    private init(config: ShellSnapshotConfig?, credentialBroker: SnapshotCredentialBrokerChannel?) {
        self.config = config
        self.credentialBroker = credentialBroker
    }

    func setCredentialBroker(_ state: SnapshotCredentialBrokerState) -> Bool {
        guard let credentialBroker else { return false }
        return credentialBroker.sendReplace(state) != state
    }

    func shouldRebuildInherited() -> Bool {
        guard let credentialBroker else { return false }
        if case .inactive = credentialBroker.current() {
            return false
        }
        return true
    }

    func build(
        cwd: PathUri,
        shell: Shell?,
        allowLoginShell: Bool,
        sandbox: ShellSnapshotSandbox?
    ) async -> ShellSnapshotFile? {
        guard let config else { return nil }
        guard let shell else { return nil }
        guard let cwd = try? cwd.toAbsPath() else { return nil }
        if let credentialBroker {
            switch credentialBroker.current() {
            case .starting, .unavailable:
                return nil
            case .inactive where config.preferExecutorSnapshots:
                return nil
            case .inactive, .ready:
                break
            }
        }
        _ = allowLoginShell
        return await Self.tryCreate(
            codexHome: config.codexHome,
            sessionId: config.sessionId,
            sessionCwd: cwd,
            shell: shell,
            sandbox: sandbox
        )
    }

    private static func tryCreate(
        codexHome: AbsolutePathBuf,
        sessionId: ThreadId,
        sessionCwd: AbsolutePathBuf,
        shell: Shell,
        sandbox: ShellSnapshotSandbox?
    ) async -> ShellSnapshotFile? {
        let extensionName: String
        switch shell.shellType {
        case .powerShell:
            return nil
        case .cmd:
            return nil
        case .zsh, .bash, .sh:
            extensionName = "sh"
        }
        let nonce = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let path = codexHome
            .join(SNAPSHOT_DIR)
            .join("\(sessionId).\(nonce).\(extensionName)")
        let tempPath = codexHome
            .join(SNAPSHOT_DIR)
            .join("\(sessionId).tmp-\(nonce)")
        Task {
            cleanupStaleSnapshots(codexHome: codexHome, sessionId: sessionId)
        }
        do {
            try await writeShellSnapshot(
                shell: shell,
                outputPath: tempPath,
                cwd: sessionCwd,
                sandbox: sandbox
            )
            try FileManager.default.moveItem(atPath: tempPath.asPath, toPath: path.asPath)
            return ShellSnapshotFile(path: path)
        } catch {
            try? FileManager.default.removeItem(atPath: tempPath.asPath)
            return nil
        }
    }
}

struct ShellSnapshotFile: Equatable, Sendable {
    var path: AbsolutePathBuf
}

private func writeShellSnapshot(
    shell: Shell,
    outputPath: AbsolutePathBuf,
    cwd: AbsolutePathBuf,
    sandbox: ShellSnapshotSandbox?
) async throws {
    if let parent = outputPath.parent {
        try FileManager.default.createDirectory(
            atPath: parent.asPath,
            withIntermediateDirectories: true
        )
    }
    let snapshot = try await captureSnapshot(shell: shell, cwd: cwd, sandbox: sandbox)
    try snapshot.write(toFile: outputPath.asPath, atomically: true, encoding: .utf8)
}

private func captureSnapshot(
    shell: Shell,
    cwd: AbsolutePathBuf,
    sandbox: ShellSnapshotSandbox?
) async throws -> String {
    let args = shell.deriveExecArgs("export -p", useLoginShell: true)
    if let sandbox {
        return try await sandbox.run(
            args: args,
            cwd: cwd,
            env: ProcessInfo.processInfo.environment,
            snapshotTimeout: SNAPSHOT_TIMEOUT,
            shellName: shell.name(),
            snapshotReadPath: nil
        )
    }
    return try await runLocalSnapshot(args: args, cwd: cwd)
}

private func runLocalSnapshot(args: [String], cwd: AbsolutePathBuf) async throws -> String {
    guard let program = args.first else {
        throw CodexErr.fatal("shell snapshot command is empty")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: program)
    process.arguments = Array(args.dropFirst())
    process.currentDirectoryURL = URL(fileURLWithPath: cwd.asPath)
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    try process.run()
    let deadline = Date().addingTimeInterval(10)
    while process.isRunning && Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    if process.isRunning {
        process.terminate()
        throw CodexErr.fatal("Snapshot command timed out")
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw CodexErr.fatal("Snapshot command exited with status \(process.terminationStatus)")
    }
    return String(data: data, encoding: .utf8) ?? ""
}

private func cleanupStaleSnapshots(codexHome: AbsolutePathBuf, sessionId: ThreadId) {
    let dir = codexHome.join(SNAPSHOT_DIR).asPath
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(atPath: dir) else { return }
    let prefix = "\(sessionId)."
    let cutoff = Date().addingTimeInterval(-SNAPSHOT_RETENTION_SECONDS)
    for entry in entries where entry.hasPrefix(prefix) {
        let path = (dir as NSString).appendingPathComponent(entry)
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date else {
            continue
        }
        if modified < cutoff {
            try? fileManager.removeItem(atPath: path)
        }
    }
}
