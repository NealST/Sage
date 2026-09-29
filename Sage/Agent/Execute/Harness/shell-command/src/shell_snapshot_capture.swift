//
//  shell_snapshot_capture.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_capture.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Capture-script generation and NUL-record decode match upstream.
//  Zsh tied arrays decode through tree-sitter + snapshotLiteralWordBytes.
//

import Foundation
import SwiftTreeSitter

private let snapshotCommandHelper = #"""
__codex_snapshot_command() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@"
  else
    command -p "$@"
  fi
}
"""#

private let snapshotEnvironment = #"""
if command -v env >/dev/null 2>&1; then
  "env" -0
else
  # Resolve the fallback separately: Bash's command -p changes the utility's PATH.
  "$(PATH="$(command -p getconf PATH)" command -v env)" -0
fi

"""#

/// Selects startup behavior and the records needed by a snapshot consumer.
public struct SnapshotCaptureOptions: Equatable, Sendable {
    public var startup: SnapshotStartup
    public var declarations: Bool
    public var environment: Bool

    public init(startup: SnapshotStartup, declarations: Bool, environment: Bool) {
        self.startup = startup
        self.declarations = declarations
        self.environment = environment
    }
}

/// Returns a script that captures native state, aliases, and the requested export records.
public func snapshotCaptureScript(
    _ shellType: ShellType,
    options: SnapshotCaptureOptions
) -> String? {
    let script: String
    switch shellType {
    case .zsh: script = zshSnapshotScript(options.startup)
    case .bash: script = bashSnapshotScript(options.startup)
    case .sh: script = shSnapshotScript(options.startup)
    case .powerShell, .cmd: return nil
    }
    let declarations = options.declarations ? snapshotExportScript(shellType) : ""
    let startupEnvironmentReplacement: String
    if options.declarations && options.environment {
        startupEnvironmentReplacement = #"""
        printf '\0CODEX_SNAPSHOT_POSIX_STARTUP\0%s\0' "$__codex_env_file"
            SNAPSHOT_ENVIRONMENT
            printf '\0'
        """#
    } else {
        startupEnvironmentReplacement = ""
    }
    return script
        .replacingOccurrences(of: "SNAPSHOT_EXPORTS", with: declarations)
        .replacingOccurrences(
            of: "SNAPSHOT_DECLARATION_ENVIRONMENT",
            with: options.declarations ? snapshotEnvironment : "")
        .replacingOccurrences(of: "SNAPSHOT_COMMAND_HELPER", with: snapshotCommandHelper)
        .replacingOccurrences(of: "SNAPSHOT_STARTUP_ENVIRONMENT", with: startupEnvironmentReplacement)
        .replacingOccurrences(
            of: "SNAPSHOT_ENVIRONMENT",
            with: options.environment ? snapshotEnvironment : "")
}

private func zshSnapshotScript(_ startup: SnapshotStartup) -> String {
    let prefix = startup == .interactive ? shellStartupScript(.zsh) : ""
    let script = #"""
    print '# Snapshot file'
    print '# Unset all aliases to avoid conflicts with functions'
    print 'unalias -a 2>/dev/null || true'
    print '# Functions'
    functions
    print ''
    SNAPSHOT_COMMAND_HELPER
    setopt_count=$(setopt | __codex_snapshot_command wc -l | __codex_snapshot_command tr -d ' ')
    print "# setopts $setopt_count"
    setopt | __codex_snapshot_command sed 's/^/setopt /'
    print ''
    printf '\0'
    alias_count=$(alias -L | __codex_snapshot_command wc -l | __codex_snapshot_command tr -d ' ')
    print "# aliases $alias_count"
    alias -L
    print ''
    printf '\0'
    SNAPSHOT_EXPORTS
    printf '\0'
    SNAPSHOT_ENVIRONMENT

    """#
    return prefix + script
}

private func bashSnapshotScript(_ startup: SnapshotStartup) -> String {
    let prefix = startup == .interactive ? shellStartupScript(.bash) : ""
    let script = #"""
    echo '# Snapshot file'
    echo '# Unset all aliases to avoid conflicts with functions'
    echo 'unalias -a 2>/dev/null || true'
    shopt -p || true
    echo '# Functions'
    declare -f
    echo ''
    SNAPSHOT_COMMAND_HELPER
    bash_opts=$(set -o | __codex_snapshot_command awk '$2=="on"{print $1}')
    bash_opt_count=$(printf '%s\n' "$bash_opts" | __codex_snapshot_command sed '/^$/d' | __codex_snapshot_command wc -l | __codex_snapshot_command tr -d ' ')
    echo "# setopts $bash_opt_count"
    if [ -n "$bash_opts" ]; then
      printf 'set -o %s\n' $bash_opts
    fi
    echo ''
    printf '\0'
    alias_count=$(alias -p | __codex_snapshot_command wc -l | __codex_snapshot_command tr -d ' ')
    echo "# aliases $alias_count"
    alias -p
    echo ''
    printf '\0'
    SNAPSHOT_EXPORTS
    printf '\0'
    SNAPSHOT_ENVIRONMENT

    """#
    return prefix + script
}

let bashShSnapshotHeader = "# Snapshot file\n# Bash-backed sh\n"

private func shSnapshotScript(_ startup: SnapshotStartup) -> String {
    let prefix: String
    if startup == .interactive {
        prefix = posixEnvPathExpansionFunction() + "\n" + #"""
        if [ -n "${ENV-}" ]; then
          __codex_env_file=$(__codex_snapshot_expand_env "$ENV")
          if [ -r "$__codex_env_file" ] && [ ! -d "$__codex_env_file" ]; then
            SNAPSHOT_STARTUP_ENVIRONMENT
            case "$__codex_env_file" in
              /*) . "$__codex_env_file" ;;
              *) . "./$__codex_env_file" ;;
            esac
          fi
          command unset __codex_env_file
        fi
        command unset -f __codex_snapshot_expand_env

        """#
    } else {
        prefix = ""
    }
    let script = #"""
    echo '# Snapshot file'
    if [ -n "${BASH_VERSINFO-}" ]; then
      echo '# Bash-backed sh'
      shopt -p || true
    fi
    echo '# Unset all aliases to avoid conflicts with functions'
    unalias -a 2>/dev/null || true
    echo '# Functions'
    if command -v typeset >/dev/null 2>&1; then
      typeset -f
    elif command -v declare >/dev/null 2>&1; then
      declare -f
    fi
    echo ''
    SNAPSHOT_COMMAND_HELPER
    if set -o >/dev/null 2>&1; then
      sh_opts=$(set -o | __codex_snapshot_command awk '$2=="on"{print $1}')
      sh_opt_count=$(printf '%s\n' "$sh_opts" | __codex_snapshot_command sed '/^$/d' | __codex_snapshot_command wc -l | __codex_snapshot_command tr -d ' ')
      echo "# setopts $sh_opt_count"
      if [ -n "$sh_opts" ]; then
        printf 'set -o %s\n' $sh_opts
      fi
    else
      echo '# setopts 0'
    fi
    echo ''
    printf '\0'
    if alias >/dev/null 2>&1; then
      alias_count=$(alias | __codex_snapshot_command wc -l | __codex_snapshot_command tr -d ' ')
      echo "# aliases $alias_count"
      alias
      echo ''
    else
      echo '# aliases 0'
    fi
    printf '\0'
    SNAPSHOT_EXPORTS
    printf '\0'
    SNAPSHOT_DECLARATION_ENVIRONMENT
    printf '\0'
    SNAPSHOT_ENVIRONMENT

    """#
    return prefix + script
}

public struct CapturedStartupEnvironment: Equatable, Sendable {
    public var path: String
    public var environment: [UInt8]
}

struct CapturedArray: Equatable, Sendable {
    var span: Range<Int>
    var values: [[UInt8]]
    var separator: [UInt8]
}

enum ExportValue: Equatable, Sendable {
    case plain
    case tiedArray(CapturedArray)
    case unparsedArray
}

struct CapturedExport: Equatable, Sendable {
    var source: String
    var key: String
    var value: ExportValue
}

/// Native shell sections captured before applying credential or environment policy.
public struct CapturedSnapshot: Equatable, Sendable {
    public var startupEnvironment: CapturedStartupEnvironment?
    var shellType: ShellType
    var state: String
    var aliases: String
    var exports: [CapturedExport]
    public var environment: [UInt8]

    /// Decode the local capture format emitted by `snapshotCaptureScript`.
    public static func parse(shellType: ShellType, captured: [UInt8]) -> CapturedSnapshot? {
        guard shellType == .bash || shellType == .zsh || shellType == .sh else { return nil }
        var remaining = captured[...]
        let startupMarker = Array("\0CODEX_SNAPSHOT_POSIX_STARTUP\0".utf8)
        var startupEnvironment: CapturedStartupEnvironment?
        if shellType == .sh,
           let start = remaining.firstIndex(ofSequence: startupMarker) {
            remaining = remaining[(start + startupMarker.count)...]
            guard let pathBytes = takeRecord(&remaining) else { return nil }
            let path = String(decoding: pathBytes, as: UTF8.self)
            let environmentStart = remaining
            while true {
                guard let entry = takeRecord(&remaining) else { return nil }
                if entry.isEmpty { break }
            }
            let consumed = environmentStart.count - remaining.count
            let environment = Array(environmentStart.prefix(max(0, consumed - 1)))
            startupEnvironment = CapturedStartupEnvironment(path: path, environment: environment)
        }
        guard let stateRecord = takeRecord(&remaining) else { return nil }
        let marker = Array("# Snapshot file".utf8)
        guard let start = stateRecord.firstIndex(ofSequence: marker),
              let state = String(bytes: stateRecord[start...], encoding: .utf8),
              let aliasBytes = takeRecord(&remaining),
              let aliases = String(bytes: aliasBytes, encoding: .utf8)
        else { return nil }

        var records: [CapturedExport] = []
        while true {
            guard let keyBytes = takeRecord(&remaining),
                  let key = String(bytes: keyBytes, encoding: .utf8)
            else { return nil }
            if key.isEmpty {
                if shellType == .sh {
                    while let entry = takeRecord(&remaining), !entry.isEmpty {
                        guard let equals = entry.firstIndex(of: UInt8(ascii: "=")) else { return nil }
                        let keyBytes = entry[..<equals]
                        guard let entryKey = String(bytes: keyBytes, encoding: .utf8) else { continue }
                        if entryKey.isEmpty || entryKey == "PWD" || entryKey == "OLDPWD" { continue }
                        if !isExportIdentifier(entryKey) { continue }
                        let value = String(decoding: entry[entry.index(after: equals)...], as: UTF8.self)
                        records.append(CapturedExport(
                            source: "export \(entryKey)=\(posixShlexQuoteValue(value))\n",
                            key: entryKey,
                            value: .plain))
                    }
                }
                return CapturedSnapshot(
                    startupEnvironment: startupEnvironment,
                    shellType: shellType,
                    state: state,
                    aliases: aliases,
                    exports: records,
                    environment: Array(remaining))
            }
            guard let sourceBytes = takeRecord(&remaining) else { return nil }
            let source = String(decoding: sourceBytes, as: UTF8.self)
            let tied = shellType == .zsh
                && source.split(whereSeparator: \.isWhitespace)
                    .dropFirst()
                    .prefix(while: { $0.hasPrefix("-") })
                    .contains(where: { $0.contains("T") })
            records.append(CapturedExport(
                source: source,
                key: key,
                value: decodeExportValue(source, shellType: shellType, tied: tied)))
        }
    }

    public func renderState() -> String {
        state + aliases
    }

    public func renderScript() -> String {
        var script = renderState()
        script.append("# exports (native declarations)\n")
        for export in exports {
            script.append(export.source)
        }
        return script
    }
}

public func captureShellSnapshot(_ shell: DetectedShell) async throws -> ShellSnapshot {
    ShellSnapshot(shellType: shell.shellType)
}

private func decodeExportValue(_ source: String, shellType: ShellType, tied: Bool) -> ExportValue {
    guard tied else { return .plain }
    guard let tree = tryParseShell(source),
          let root = tree.rootNode,
          !root.hasError,
          let first = root.namedChild(at: 0)
    else { return .unparsedArray }
    let array = (0..<first.namedChildCount)
        .compactMap { first.namedChild(at: $0) }
        .compactMap { child -> Node? in
            guard let value = child.child(byFieldName: "value"), value.nodeType == "array" else {
                return nil
            }
            return value
        }
        .first
    guard let array else { return .unparsedArray }
    let values = (0..<array.namedChildCount).compactMap { index -> [UInt8]? in
        guard let node = array.namedChild(at: index) else { return nil }
        return snapshotLiteralWordBytes(node, script: source, shellType: shellType, quoting: .posix)
    }
    let decodedValues: [[UInt8]]?
    if values.count == array.namedChildCount {
        decodedValues = values
    } else {
        decodedValues = nil
    }
    let sibling = array.parent?.nextNamedSibling
    let separator: [UInt8]?
    if let sibling, sibling.nodeType == "variable_name" {
        separator = nodeUtf8Bytes(sibling, source)
    } else if let sibling {
        separator = snapshotLiteralWordBytes(
            sibling, script: source, shellType: shellType, quoting: .posix
        )
    } else {
        separator = [UInt8(ascii: ":")]
    }
    if let decodedValues, let separator {
        return .tiedArray(CapturedArray(
            span: utf16Range(array),
            values: decodedValues,
            separator: separator
        ))
    }
    return .unparsedArray
}

private func utf16Range(_ node: Node) -> Range<Int> {
    Int(node.byteRange.lowerBound) / 2 ..< Int(node.byteRange.upperBound) / 2
}

private func nodeUtf8Bytes(_ node: Node, _ source: String) -> [UInt8]? {
    utf16Slice(
        source,
        Int(node.byteRange.lowerBound) / 2,
        Int(node.byteRange.upperBound) / 2
    ).map { Array($0.utf8) }
}

private func takeRecord(_ remaining: inout ArraySlice<UInt8>) -> [UInt8]? {
    guard let boundary = remaining.firstIndex(of: 0) else { return nil }
    let record = Array(remaining[..<boundary])
    remaining = remaining[remaining.index(after: boundary)...]
    return record
}

private func isExportIdentifier(_ key: String) -> Bool {
    key.utf8.enumerated().allSatisfy { index, byte in
        byte == 0x5f
            || (0x41...0x5a).contains(byte)
            || (0x61...0x7a).contains(byte)
            || (index > 0 && (0x30...0x39).contains(byte))
    }
}

private func posixShlexQuoteValue(_ token: String) -> String {
    if token.isEmpty { return "''" }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%+=:,./-_"))
    if token.unicodeScalars.allSatisfy({ safe.contains($0) }) { return token }
    return "'" + token.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private extension Collection where Element == UInt8 {
    func firstIndex(ofSequence needle: [UInt8]) -> Index? {
        guard !needle.isEmpty, count >= needle.count else { return nil }
        var index = startIndex
        while distance(from: index, to: endIndex) >= needle.count {
            if self[index..<(self.index(index, offsetBy: needle.count))].elementsEqual(needle) {
                return index
            }
            formIndex(after: &index)
        }
        return nil
    }
}
