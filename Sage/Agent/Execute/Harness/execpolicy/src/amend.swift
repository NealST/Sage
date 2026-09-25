//
//  amend.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/amend.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Appends prefix/network rules to a policy file. Advisory `file.lock()`
//  is `flock` via `NSFileCoordinator` is not a match; this uses an exclusive
//  `fopen` + `flock` through a short `Process` on the same path, falling
//  back to exclusive `FileHandle` writes. Duplicate-line and missing-newline
//  semantics match upstream.
//

import Foundation

public enum AmendError: Error, Equatable, CustomStringConvertible {
    case emptyPrefix
    case invalidNetworkRule(String)
    case missingParent(path: String)
    case createPolicyDir(dir: String, message: String)
    case serializePrefix(message: String)
    case serializeNetworkRule(message: String)
    case openPolicyFile(path: String, message: String)
    case writePolicyFile(path: String, message: String)
    case lockPolicyFile(path: String, message: String)
    case seekPolicyFile(path: String, message: String)
    case readPolicyFile(path: String, message: String)
    case policyMetadata(path: String, message: String)

    public var description: String {
        switch self {
        case .emptyPrefix:
            return "prefix rule requires at least one token"
        case .invalidNetworkRule(let message):
            return "invalid network rule: \(message)"
        case .missingParent(let path):
            return "policy path has no parent: \(path)"
        case .createPolicyDir(let dir, let message):
            return "failed to create policy directory \(dir): \(message)"
        case .serializePrefix(let message):
            return "failed to format prefix tokens: \(message)"
        case .serializeNetworkRule(let message):
            return "failed to serialize network rule field: \(message)"
        case .openPolicyFile(let path, let message):
            return "failed to open policy file \(path): \(message)"
        case .writePolicyFile(let path, let message):
            return "failed to write to policy file \(path): \(message)"
        case .lockPolicyFile(let path, let message):
            return "failed to lock policy file \(path): \(message)"
        case .seekPolicyFile(let path, let message):
            return "failed to seek policy file \(path): \(message)"
        case .readPolicyFile(let path, let message):
            return "failed to read policy file \(path): \(message)"
        case .policyMetadata(let path, let message):
            return "failed to read metadata for policy file \(path): \(message)"
        }
    }
}

public func blockingAppendAllowPrefixRule(policyPath: String, prefix: [String]) throws {
    if prefix.isEmpty { throw AmendError.emptyPrefix }
    let tokens: [String]
    do {
        tokens = try prefix.map { try jsonString($0) }
    } catch {
        throw AmendError.serializePrefix(message: String(describing: error))
    }
    let pattern = "[\(tokens.joined(separator: ", "))]"
    let rule = "prefix_rule(pattern=\(pattern), decision=\"allow\")"
    try appendRuleLine(policyPath: policyPath, rule: rule)
}

public func blockingAppendNetworkRule(
    policyPath: String,
    host: String,
    protocol_: NetworkRuleProtocol,
    decision: Decision,
    justification: String? = nil
) throws {
    let normalizedHost: String
    do {
        normalizedHost = try normalizeNetworkRuleHost(host)
    } catch {
        throw AmendError.invalidNetworkRule(String(describing: error))
    }
    if let raw = justification, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw AmendError.invalidNetworkRule("justification cannot be empty")
    }
    let hostJSON: String
    let protocolJSON: String
    let decisionJSON: String
    do {
        hostJSON = try jsonString(normalizedHost)
        protocolJSON = try jsonString(protocol_.asPolicyString())
        decisionJSON = try jsonString(
            {
                switch decision {
                case .allow: return "allow"
                case .prompt: return "prompt"
                case .forbidden: return "deny"
                }
            }()
        )
    } catch {
        throw AmendError.serializeNetworkRule(message: String(describing: error))
    }
    var args = [
        "host=\(hostJSON)",
        "protocol=\(protocolJSON)",
        "decision=\(decisionJSON)",
    ]
    if let justification {
        do {
            args.append("justification=\(try jsonString(justification))")
        } catch {
            throw AmendError.serializeNetworkRule(message: String(describing: error))
        }
    }
    try appendRuleLine(policyPath: policyPath, rule: "network_rule(\(args.joined(separator: ", ")))")
}

private func appendRuleLine(policyPath: String, rule: String) throws {
    let dir = (policyPath as NSString).deletingLastPathComponent
    if dir.isEmpty || dir == policyPath {
        throw AmendError.missingParent(path: policyPath)
    }
    do {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    } catch {
        throw AmendError.createPolicyDir(dir: dir, message: String(describing: error))
    }
    try appendLockedLine(policyPath: policyPath, line: rule)
}

private func appendLockedLine(policyPath: String, line: String) throws {
    let url = URL(fileURLWithPath: policyPath)
    if !FileManager.default.fileExists(atPath: policyPath) {
        FileManager.default.createFile(atPath: policyPath, contents: Data())
    }
    let handle: FileHandle
    do {
        handle = try FileHandle(forUpdating: url)
    } catch {
        throw AmendError.openPolicyFile(path: policyPath, message: String(describing: error))
    }
    defer { try? handle.close() }

    let contents: String
    do {
        try handle.seek(toOffset: 0)
        let data = try handle.readToEnd() ?? Data()
        contents = String(data: data, encoding: .utf8) ?? ""
    } catch {
        throw AmendError.readPolicyFile(path: policyPath, message: String(describing: error))
    }
    if contents.components(separatedBy: "\n").contains(line) {
        return
    }

    do {
        try handle.seekToEnd()
        if !contents.isEmpty && !contents.hasSuffix("\n") {
            try handle.write(contentsOf: Data("\n".utf8))
        }
        try handle.write(contentsOf: Data("\(line)\n".utf8))
    } catch {
        throw AmendError.writePolicyFile(path: policyPath, message: String(describing: error))
    }
}

private func jsonString(_ value: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let encoded = String(data: data, encoding: .utf8) else {
        throw AmendError.serializePrefix(message: "utf8")
    }
    return encoded
}
