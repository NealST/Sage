//
//  shell_snapshot_credentials.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_credentials.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Apply credential and environment policy to captured exports. The shared
//  literal decoder still validates alias and function bodies without
//  evaluating them.
//

import Foundation

/// Environment views used to render protected credential references into a shell snapshot.
public struct SnapshotCredentialEnvironment: Sendable {
    public var original: [String: String]
    public var restored: [String: String]
    public var configured: [String: String]
    public var discovered: [String: String]
    public var allowed: [String: String]
    public var isAllowedUnset: @Sendable (String) -> Bool
    public var brokeredKeys: [String]
    public var brokeredAliasKeys: [String]
    public var allowedBrokeredKeys: [String]

    public init(
        original: [String: String],
        restored: [String: String],
        configured: [String: String],
        discovered: [String: String],
        allowed: [String: String],
        isAllowedUnset: @escaping @Sendable (String) -> Bool,
        brokeredKeys: [String],
        brokeredAliasKeys: [String],
        allowedBrokeredKeys: [String]
    ) {
        self.original = original
        self.restored = restored
        self.configured = configured
        self.discovered = discovered
        self.allowed = allowed
        self.isAllowedUnset = isAllowedUnset
        self.brokeredKeys = brokeredKeys
        self.brokeredAliasKeys = brokeredAliasKeys
        self.allowedBrokeredKeys = allowedBrokeredKeys
    }
}

/// Credential-checked replay script and aliases to restore after shell startup.
public struct PreparedSnapshot: Equatable, Sendable {
    public var script: String
    public var aliases: [String: String]
    public var rejectedAliasKeys: [String]

    public init(script: String, aliases: [String: String], rejectedAliasKeys: [String]) {
        self.script = script
        self.aliases = aliases
        self.rejectedAliasKeys = rejectedAliasKeys
    }
}

public func looksLikeCredentialName(_ name: String) -> Bool {
    let upper = name.uppercased()
    return ["TOKEN", "SECRET", "PASSWORD", "PASSWD", "API_KEY", "ACCESS_KEY", "PRIVATE_KEY"]
        .contains { upper.contains($0) }
}

/// Prepare a replay script from captured state without changing the captured data.
public func prepareSnapshotCredentials(
    captured: CapturedSnapshot,
    environment: SnapshotCredentialEnvironment,
    virtualizeText: (inout String) -> Bool
) -> PreparedSnapshot? {
    var virtualizeText = virtualizeText
    func realCredentialValue(_ key: String) -> String? {
        environment.restored[key] ?? environment.configured[key]
    }
    var credentialAliases: [String: [String]] = [:]
    for (key, value) in environment.original {
        if environment.brokeredKeys.contains(key) || environment.brokeredAliasKeys.contains(key) {
            continue
        }
        let credentialKeys = environment.brokeredKeys.filter { credentialKey in
            if let real = realCredentialValue(credentialKey),
               value == real
                || (value.contains(real)
                    && (real.count >= 16
                        || (environment.discovered[credentialKey].map { dummy in
                            environment.discovered[key].map { virtualized in
                                virtualized != value && virtualized.contains(dummy)
                            } ?? false
                        } ?? false))) {
                return true
            }
            return [environment.original[credentialKey], environment.discovered[credentialKey]]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .contains { dummy in
                    if value == dummy { return true }
                    if value.contains(dummy) && dummy.count >= 16 { return true }
                    if value.contains(dummy), let real = realCredentialValue(credentialKey) {
                        var restored = value.replacingOccurrences(of: dummy, with: real)
                        return restored != value
                            && virtualizeText(&restored)
                            && environment.discovered[key] == restored
                    }
                    return false
                }
        }
        if !credentialKeys.isEmpty, isExportIdentifier(key) {
            credentialAliases[key] = credentialKeys
        }
    }

    func credentialAliasAssignment(
        _ value: String,
        credentialKeys: [String]
    ) -> (SnapshotValue, String)? {
        var remaining = value
        var assignment = SnapshotValue()
        var normalized = ""
        while !remaining.isEmpty {
            let nextCredential = credentialKeys.compactMap { credentialKey -> (Int, String, String)? in
                guard let dummy = environment.discovered[credentialKey],
                      let real = realCredentialValue(credentialKey) else { return nil }
                let allowedKey = environment.allowedBrokeredKeys.first { $0 == credentialKey }
                    ?? environment.allowedBrokeredKeys.first { realCredentialValue($0) == real }
                guard let allowedKey else { return nil }
                guard let index = remaining.range(of: dummy)?.lowerBound else { return nil }
                return (remaining.distance(from: remaining.startIndex, to: index), allowedKey, dummy)
            }.min(by: { $0.0 < $1.0 })
            guard let (index, credentialKey, dummy) = nextCredential else {
                assignment.parts.append(.literal(remaining))
                normalized.append(remaining)
                break
            }
            if index != 0 {
                let prefix = String(remaining.prefix(index))
                assignment.parts.append(.literal(prefix))
                normalized.append(prefix)
            }
            assignment.parts.append(.credential(key: credentialKey))
            guard let allowed = environment.allowed[credentialKey] else { return nil }
            normalized.append(allowed)
            remaining = String(remaining.dropFirst(index + dummy.count))
        }
        return (assignment, normalized)
    }

    func credentialAliasIsAllowed(_ credentialKeys: [String]) -> Bool {
        credentialKeys.allSatisfy { credentialKey in
            guard let real = realCredentialValue(credentialKey) else { return false }
            return environment.allowedBrokeredKeys.contains { realCredentialValue($0) == real }
        }
    }

    func isDisallowedCredentialAlias(_ key: String) -> Bool {
        guard let value = environment.original[key] else { return false }
        var virtualized = value
        return !virtualizeText(&virtualized)
    }

    var aliasValues: [String: String] = [:]
    var rejectedAliasKeys: [String] = []
    var invalidExport = false
    var exports: [SnapshotExport] = []
    for export in captured.exports {
        let line = export.source
        let key = export.key
        if (!environment.allowed.keys.contains(key)
            && (environment.original.keys.contains(key) || !environment.isAllowedUnset(key)))
            || environment.brokeredKeys.contains(key) {
            continue
        }
        if environment.configured.keys.contains(key), case .tiedArray(let array) = export.value {
            guard let value = environment.allowed[key] else { continue }
            var virtualized = value
            if !virtualizeText(&virtualized) || virtualized != value {
                invalidExport = true
                exports.append(.captured(line))
                continue
            }
            if credentialAliases.removeValue(forKey: key) != nil {
                aliasValues[key] = value
            }
            guard let prefix = utf16Slice(line, 0, array.span.lowerBound)?.stripSuffix("=") else {
                continue
            }
            let suffix = utf16Slice(line, array.span.upperBound, utf16Count(line)) ?? ""
            exports.append(.arrayBinding(key: key, declaration: prefix, suffix: suffix))
            continue
        }
        if isDisallowedCredentialAlias(key) {
            continue
        }
        if environment.brokeredAliasKeys.contains(key) {
            if case .tiedArray(let array) = export.value,
               let prefix = utf16Slice(line, 0, array.span.lowerBound)?.stripSuffix("=") {
                let suffix = utf16Slice(line, array.span.upperBound, utf16Count(line)) ?? ""
                exports.append(.arrayBinding(key: key, declaration: prefix, suffix: suffix))
            }
            continue
        }
        if let credentialKeys = credentialAliases.removeValue(forKey: key) {
            if !credentialAliasIsAllowed(credentialKeys) {
                rejectedAliasKeys.append(key)
                continue
            }
            let declaration: String
            if let eq = line.firstIndex(of: "=") {
                declaration = String(line[..<eq])
            } else {
                declaration = trimTrailingWhitespace(line)
            }
            guard let allowed = environment.allowed[key],
                  let (assignment, value) = credentialAliasAssignment(allowed, credentialKeys: credentialKeys)
            else { continue }
            aliasValues[key] = value
            if case .tiedArray(let array) = export.value {
                let scalar = joinBytes(array.values, separator: array.separator)
                let crossesElement = credentialKeys
                    .flatMap { key -> [String] in
                        [realCredentialValue(key), environment.original[key], environment.discovered[key]]
                            .compactMap { $0 }
                    }
                    .filter { !$0.isEmpty }
                    .contains { credential in
                        let credentialBytes = Array(credential.utf8)
                        guard credentialBytes.count > 0 else { return false }
                        return windows(scalar, credentialBytes.count).enumerated().contains { start, bytes in
                            guard bytes.elementsEqual(credentialBytes) else { return false }
                            var offset = 0
                            return !array.values.contains { value in
                                let contains = offset <= start
                                    && start + credentialBytes.count <= offset + value.count
                                offset += value.count + array.separator.count
                                return contains
                            }
                        }
                    }
                if crossesElement {
                    invalidExport = true
                    exports.append(.captured(line))
                    continue
                }
                var elements: [SnapshotValue] = []
                var normalized: [String] = []
                var decoded = true
                for bytes in array.values {
                    guard var text = String(bytes: bytes, encoding: .utf8),
                          virtualizeText(&text),
                          let assigned = credentialAliasAssignment(text, credentialKeys: credentialKeys)
                    else {
                        decoded = false
                        break
                    }
                    elements.append(assigned.0)
                    normalized.append(assigned.1)
                }
                if !decoded {
                    invalidExport = true
                    exports.append(.captured(line))
                    continue
                }
                let joined = joinBytes(normalized.map { Array($0.utf8) }, separator: array.separator)
                if joined != Array((environment.allowed[key] ?? "").utf8) {
                    invalidExport = true
                    exports.append(.captured(line))
                    continue
                }
                let prefix = utf16Slice(line, 0, array.span.lowerBound) ?? ""
                let suffix = utf16Slice(line, array.span.upperBound, utf16Count(line)) ?? ""
                exports.append(.array(prefix: prefix, elements: elements, suffix: suffix))
                continue
            }
            if case .unparsedArray = export.value {
                invalidExport = true
                exports.append(.captured(line))
                continue
            }
            exports.append(.assignment(declaration: declaration, value: assignment))
            continue
        }
        exports.append(.captured(line))
    }

    guard let snapshot = renderSnapshot(
        state: captured.state, aliases: captured.aliases, exports: exports
    ) else { return nil }
    if invalidExport { return nil }

    for (key, credentialKeys) in credentialAliases {
        if !isDisallowedCredentialAlias(key),
           credentialAliasIsAllowed(credentialKeys),
           let allowed = environment.allowed[key],
           let (_, value) = credentialAliasAssignment(allowed, credentialKeys: credentialKeys) {
            aliasValues[key] = value
        } else {
            rejectedAliasKeys.append(key)
        }
    }

    var virtualized = snapshot
    if !virtualizeText(&virtualized) || virtualized != snapshot {
        return nil
    }
    guard let words = snapshotLiteralWords(snapshot, shellType: captured.shellType) else {
        return nil
    }
    for word in words {
        var copy = word
        if !virtualizeText(&copy) || copy != word {
            return nil
        }
    }
    return PreparedSnapshot(
        script: snapshot,
        aliases: aliasValues,
        rejectedAliasKeys: rejectedAliasKeys
    )
}

private func isExportIdentifier(_ key: String) -> Bool {
    key.utf8.enumerated().allSatisfy { index, byte in
        byte == 0x5f
            || (0x41...0x5a).contains(byte)
            || (0x61...0x7a).contains(byte)
            || (index != 0 && (0x30...0x39).contains(byte))
    }
}

private func joinBytes(_ parts: [[UInt8]], separator: [UInt8]) -> [UInt8] {
    guard let first = parts.first else { return [] }
    var out = first
    for part in parts.dropFirst() {
        out.append(contentsOf: separator)
        out.append(contentsOf: part)
    }
    return out
}

private func windows(_ bytes: [UInt8], _ size: Int) -> [[UInt8]] {
    guard size > 0, bytes.count >= size else { return [] }
    return (0...(bytes.count - size)).map { Array(bytes[$0..<($0 + size)]) }
}

private func utf16Count(_ string: String) -> Int {
    string.utf16.count
}

private func trimTrailingWhitespace(_ string: String) -> String {
    var result = string
    while let last = result.last, last.isWhitespace {
        result.removeLast()
    }
    return result
}

private extension String {
    func stripSuffix(_ suffix: String) -> String? {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : nil
    }
}
