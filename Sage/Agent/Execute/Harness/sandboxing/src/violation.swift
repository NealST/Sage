//
//  violation.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/violation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Classifies filesystem/network sandbox denials. `tracing::warn` maps to
//  `os.Logger`. `BlockedRequest` / `NetworkMode` are the inlined type layer.
//

import CodexProtocol
import Foundation
import os

private let logger = Logger(subsystem: "com.sage.execute", category: "sandboxing")

let EXIT_CODE_SIGNAL_BASE: Int32 = 128
private let OUTPUT_SNIPPET_MAX_CHARS = 512
private let SIGSYS: Int32 = 12

private let SANDBOX_DENIED_KEYWORDS: [(FileSystemSandboxViolationReason, String)] = [
    (.operationNotPermitted, "operation not permitted"),
    (.permissionDenied, "permission denied"),
    (.readOnlyFileSystem, "read-only file system"),
    (.policyDenied, "seccomp"),
    (.policyDenied, "sandbox"),
    (.policyDenied, "landlock"),
    (.failedToWriteFile, "failed to write file"),
]

private let QUICK_REJECT_EXIT_CODES: [Int32] = [2, 126, 127]

public enum SandboxViolationEvent: Equatable, Sendable {
    case fileSystem(FileSystemSandboxViolation)
    case network(NetworkSandboxViolation)
}

public enum SandboxViolationBackend: Equatable, Sendable {
    case linuxSandbox
    case managedNetworkProxy
    case seatbelt
    case windowsSandbox
    case windowsMxc

    public func asStr() -> String {
        switch self {
        case .linuxSandbox: return "linux_sandbox"
        case .managedNetworkProxy: return "managed_network_proxy"
        case .seatbelt: return "seatbelt"
        case .windowsSandbox: return "windows_sandbox"
        case .windowsMxc: return "windows_mxc"
        }
    }
}

public struct FileSystemSandboxViolation: Equatable, Sendable {
    public var backend: SandboxViolationBackend
    public var reason: FileSystemSandboxViolationReason
    public var path: String?
    public var outputSnippet: String

    public init(
        backend: SandboxViolationBackend,
        reason: FileSystemSandboxViolationReason,
        path: String?,
        outputSnippet: String
    ) {
        self.backend = backend
        self.reason = reason
        self.path = path
        self.outputSnippet = outputSnippet
    }
}

public enum FileSystemSandboxViolationReason: Equatable, Sendable {
    case operationNotPermitted
    case permissionDenied
    case readOnlyFileSystem
    case policyDenied
    case failedToWriteFile
    case signalSyscall

    public func asStr() -> String {
        switch self {
        case .operationNotPermitted: return "operation_not_permitted"
        case .permissionDenied: return "permission_denied"
        case .readOnlyFileSystem: return "read_only_file_system"
        case .policyDenied: return "policy_denied"
        case .failedToWriteFile: return "failed_to_write_file"
        case .signalSyscall: return "sigsys"
        }
    }
}

public struct NetworkSandboxViolation: Equatable, Sendable {
    public var backend: SandboxViolationBackend
    public var host: String
    public var reason: String
    public var client: String?
    public var method: String?
    public var mode: NetworkMode?
    public var protocol_: String
    public var decision: String?
    public var source: String?
    public var port: UInt16?
    public var timestamp: Int64

    public init(
        backend: SandboxViolationBackend,
        host: String,
        reason: String,
        client: String? = nil,
        method: String? = nil,
        mode: NetworkMode? = nil,
        protocol_: String,
        decision: String? = nil,
        source: String? = nil,
        port: UInt16? = nil,
        timestamp: Int64
    ) {
        self.backend = backend
        self.host = host
        self.reason = reason
        self.client = client
        self.method = method
        self.mode = mode
        self.protocol_ = protocol_
        self.decision = decision
        self.source = source
        self.port = port
        self.timestamp = timestamp
    }

    public static func fromBlockedRequest(_ blocked: BlockedRequest) -> NetworkSandboxViolation {
        NetworkSandboxViolation(
            backend: .managedNetworkProxy,
            host: blocked.host,
            reason: blocked.reason,
            client: blocked.client,
            method: blocked.method,
            mode: blocked.mode,
            protocol_: blocked.protocol_,
            decision: blocked.decision,
            source: blocked.source,
            port: blocked.port,
            timestamp: blocked.timestamp
        )
    }
}

func classifyFilesystemSandboxViolation(
    sandboxType: SandboxType,
    execOutput: ExecToolCallOutput
) -> FileSystemSandboxViolation? {
    if execOutput.exitCode == 0 { return nil }
    let backend: SandboxViolationBackend
    switch sandboxType {
    case .none: return nil
    case .macosSeatbelt: backend = .seatbelt
    case .linuxSeccomp: backend = .linuxSandbox
    case .windowsRestrictedToken: backend = .windowsSandbox
    case .windowsMxc: backend = .windowsMxc
    }

    if let (reason, output) = filesystemReasonFromOutput(execOutput) {
        return FileSystemSandboxViolation(
            backend: backend,
            reason: reason,
            path: extractDeniedPathFromText(output),
            outputSnippet: outputSnippet(output)
        )
    }
    if QUICK_REJECT_EXIT_CODES.contains(execOutput.exitCode) {
        return nil
    }
    if sandboxType == .linuxSeccomp
        && execOutput.exitCode == EXIT_CODE_SIGNAL_BASE + SIGSYS {
        let snippet = [execOutput.stderr.text, execOutput.stdout.text, execOutput.aggregatedOutput.text]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(outputSnippet) ?? ""
        return FileSystemSandboxViolation(
            backend: backend,
            reason: .signalSyscall,
            path: nil,
            outputSnippet: snippet
        )
    }
    return nil
}

public func recordFilesystemSandboxViolation(
    sandboxType: SandboxType,
    execOutput: ExecToolCallOutput
) -> FileSystemSandboxViolation? {
    guard let violation = classifyFilesystemSandboxViolation(
        sandboxType: sandboxType,
        execOutput: execOutput
    ) else { return nil }
    recordSandboxViolation(.fileSystem(violation))
    return violation
}

public func recordNetworkSandboxViolation(_ blocked: BlockedRequest) -> NetworkSandboxViolation {
    let violation = NetworkSandboxViolation.fromBlockedRequest(blocked)
    recordSandboxViolation(.network(violation))
    return violation
}

public func recordSandboxViolation(_ event: SandboxViolationEvent) {
    switch event {
    case .fileSystem(let violation):
        logger.warning(
            "recorded sandbox violation: resource=filesystem backend=\(violation.backend.asStr(), privacy: .public) reason=\(violation.reason.asStr(), privacy: .public) path=\(violation.path ?? "unknown", privacy: .public)"
        )
    case .network(let violation):
        logger.warning(
            "recorded sandbox violation: resource=network backend=\(violation.backend.asStr(), privacy: .public) protocol=\(violation.protocol_, privacy: .public) host=\(violation.host, privacy: .public) reason=\(violation.reason, privacy: .public)"
        )
    }
}

private func filesystemReasonFromOutput(
    _ execOutput: ExecToolCallOutput
) -> (FileSystemSandboxViolationReason, String)? {
    for section in [execOutput.stderr.text, execOutput.stdout.text, execOutput.aggregatedOutput.text] {
        let lower = section.lowercased()
        if let (reason, _) = SANDBOX_DENIED_KEYWORDS.first(where: { lower.contains($0.1) }) {
            return (reason, section)
        }
    }
    return nil
}

func extractDeniedPathFromText(_ text: String) -> String? {
    let markers = [
        ": operation not permitted",
        ": permission denied",
        ": read-only file system",
    ]
    for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        for marker in markers {
            guard let markerStart = line.range(
                of: marker,
                options: [.caseInsensitive]
            )?.lowerBound else { continue }
            let candidatePrefix = String(line[..<markerStart])
            let candidate = (candidatePrefix.components(separatedBy: ": ").last ?? candidatePrefix)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if candidate.hasPrefix("/") || candidate.hasPrefix("./") || candidate.hasPrefix("../") {
                return candidate
            }
        }
    }
    return nil
}

private func outputSnippet(_ output: String) -> String {
    String(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(OUTPUT_SNIPPET_MAX_CHARS))
}
