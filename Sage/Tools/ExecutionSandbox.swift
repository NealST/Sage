//
//  ExecutionSandbox.swift
//  Sage
//
//  Shared process sandboxing and environment policy.
//  The closed-by-default Seatbelt shape follows the architecture used by
//  OpenAI Codex's macOS sandbox, without copying its policy implementation.
//

import Foundation

nonisolated struct SandboxedProcessInvocation: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
}

nonisolated struct ExecutionSandboxConfiguration: Sendable, Equatable {
    var readableRoots: [URL]
    var writableRoots: [URL]
    var protectedReadRoots: [URL]
    var protectedWriteRoots: [URL]
    var allowsNetwork: Bool

    static func shell(
        policy: PathGuard.Policy,
        readAllowlist: [String],
        writeRoot: URL? = nil,
        allowsWrites: Bool = true,
        allowsNetwork: Bool,
        allowsProtectedMetadataWrites: Bool = false,
        allowedSensitiveReadRoots: [URL] = []
    ) -> Self {
        let protectedReadRoots = SensitiveResourcePolicy.roots.filter { sensitiveRoot in
            !allowedSensitiveReadRoots.contains { allowedRoot in
                allowedRoot.standardizedFileURL.resolvingSymlinksInPath().path
                    == sensitiveRoot.standardizedFileURL.resolvingSymlinksInPath().path
            }
        }
        switch policy {
        case .home:
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Self(
                readableRoots: [home],
                writableRoots: allowsWrites ? [writeRoot ?? home] : [],
                protectedReadRoots: protectedReadRoots,
                protectedWriteRoots: allowsProtectedMetadataWrites ? [] : policyWriteProtectedRoots(root: home),
                allowsNetwork: allowsNetwork
            )

        case .project(let root):
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Self(
                readableRoots: [root] + readAllowlist.map { URL(fileURLWithPath: $0) },
                writableRoots: allowsWrites ? [writeRoot ?? root] : [],
                protectedReadRoots: [home] + protectedReadRoots,
                protectedWriteRoots: allowsProtectedMetadataWrites ? [] : policyWriteProtectedRoots(root: root),
                allowsNetwork: allowsNetwork
            )
        }
    }

    static func skillScript(policy: PathGuard.Policy, skillDirectory: URL) -> Self {
        var configuration = shell(
            policy: policy,
            readAllowlist: [skillDirectory.path],
            allowsWrites: false,
            allowsNetwork: false
        )
        if !configuration.readableRoots.contains(skillDirectory) {
            configuration.readableRoots.append(skillDirectory)
        }
        return configuration
    }

    static func mcpServer(writableRoots: [URL] = []) -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self(
            readableRoots: [home],
            writableRoots: writableRoots,
            protectedReadRoots: SensitiveResourcePolicy.roots,
            protectedWriteRoots: writableRoots.flatMap(policyWriteProtectedRoots),
            allowsNetwork: true
        )
    }

    private static func policyWriteProtectedRoots(root: URL) -> [URL] {
        [
            ".git",
            ".sage",
            ".agents",
        ].map { root.appendingPathComponent($0, isDirectory: true) }
    }
}

nonisolated enum ChildProcessEnvironment {
    private static let inheritedKeys: Set<String> = [
        "HOME",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "LOGNAME",
        "PATH",
        "SHELL",
        "TEMP",
        "TERM",
        "TMP",
        "TMPDIR",
        "USER",
    ]

    static func sanitized(overrides: [String: String] = [:]) -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var environment = inheritedKeys.reduce(into: [String: String]()) { result, key in
            if let value = parent[key] {
                result[key] = value
            }
        }
        environment["PATH"] = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOME"] = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        for (key, value) in overrides where isSafeOverrideKey(key) {
            environment[key] = value
        }
        return environment
    }

    private static func isSafeOverrideKey(_ key: String) -> Bool {
        let uppercased = key.uppercased()
        return !uppercased.hasPrefix("DYLD_")
            && !uppercased.hasPrefix("LD_")
            && !uppercased.hasPrefix("__XPC_")
    }
}

nonisolated enum ExecutionSandbox {
    private static let sandboxExecutable = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

    static func wrap(
        executable: URL,
        arguments: [String],
        configuration: ExecutionSandboxConfiguration,
        auditComponent: String = "process"
    ) -> SandboxedProcessInvocation {
        SecurityAuditLogger.sandboxLaunch(
            component: auditComponent,
            allowsNetwork: configuration.allowsNetwork,
            protectedMetadataWritable: configuration.protectedWriteRoots.isEmpty
        )
        let profile = seatbeltProfile(configuration: configuration)
        return SandboxedProcessInvocation(
            executable: sandboxExecutable,
            arguments: ["-p", profile, executable.path] + arguments
        )
    }

    static func seatbeltProfile(configuration: ExecutionSandboxConfiguration) -> String {
        let temporaryRoots = temporaryWritableRoots()
        let readableRoots = normalizedUnique(
            configuration.readableRoots + temporaryRoots + toolchainReadableRoots()
        )
        let writableRoots = normalizedUnique(configuration.writableRoots + temporaryRoots)
        let protectedReadRoots = normalizedUnique(configuration.protectedReadRoots)
        let protectedWriteRoots = normalizedUnique(configuration.protectedWriteRoots)

        var rules = [
            "(version 1)",
            "(deny default)",
            "(import \"system.sb\")",
            "(allow process-exec)",
            "(allow process-fork)",
            "(allow signal (target same-sandbox))",
            "(allow process-info* (target same-sandbox))",
            "(allow sysctl-read)",
            "(allow file-read-metadata)",
            "(allow file-read* (subpath \"/System\"))",
            "(allow file-read* (subpath \"/usr\"))",
            "(allow file-read* (subpath \"/bin\"))",
            "(allow file-read* (subpath \"/sbin\"))",
            "(allow file-read* (subpath \"/Library/Apple\"))",
            "(allow file-read* (subpath \"/Library/Frameworks\"))",
            "(allow file-read* (subpath \"/private/etc\"))",
            "(allow file-read* (subpath \"/private/var/db/timezone\"))",
            "(allow file-read* (subpath \"/dev\"))",
            "(allow file-write-data (literal \"/dev/null\"))",
            "(allow file-read* file-write* file-ioctl (literal \"/dev/ptmx\"))",
            "(allow pseudo-tty)",
        ]

        rules.append(contentsOf: protectedReadRoots.map { root in
            "(deny file-read* (subpath \"\(sandboxLiteral(root.path))\"))"
        })
        rules.append(contentsOf: protectedWriteRoots.map { root in
            "(deny file-write* (subpath \"\(sandboxLiteral(root.path))\"))"
        })
        rules.append(contentsOf: readableRoots.map { root in
            "(allow file-read* (subpath \"\(sandboxLiteral(root.path))\"))"
        })
        rules.append(contentsOf: writableRoots.map { root in
            "(allow file-write* (subpath \"\(sandboxLiteral(root.path))\"))"
        })
        rules.append(configuration.allowsNetwork ? "(allow network*)" : "(deny network*)")
        return rules.joined(separator: "\n")
    }

    private static func temporaryWritableRoots() -> [URL] {
        [
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            URL(fileURLWithPath: "/private/var/folders", isDirectory: true),
        ]
    }

    private static func toolchainReadableRoots() -> [URL] {
        let pathEntries = ChildProcessEnvironment.sanitized()["PATH", default: ""]
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        return pathEntries.map { entry in
            let path = entry.standardizedFileURL.path
            if path.hasPrefix("/opt/homebrew/") {
                return URL(fileURLWithPath: "/opt/homebrew", isDirectory: true)
            }
            if path.hasPrefix("/usr/local/") {
                return URL(fileURLWithPath: "/usr/local", isDirectory: true)
            }
            return entry
        }
    }

    private static func normalizedUnique(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.compactMap { root in
            let normalized = root.standardizedFileURL.resolvingSymlinksInPath()
            return seen.insert(normalized.path).inserted ? normalized : nil
        }
    }

    private static func sandboxLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
