//
//  SeatbeltSandbox.swift
//  Sage
//
//  Kernel-level sandboxing for shell commands via /usr/bin/sandbox-exec.
//

import Foundation

/// A fully prepared process invocation, sandboxed when Seatbelt is present.
struct SeatbeltInvocation: Sendable {
    let executable: URL
    let arguments: [String]
    /// Full replacement environment, or nil to inherit the parent's.
    let environment: [String: String]?
}

/// Wraps shell invocations with a Seatbelt profile derived from the active
/// `PathGuard` policy: General may write under `~`, Project under its root.
/// Project additionally loses read access to the rest of the home directory,
/// except paths re-allowed through `PathGuard.readAllowlist`.
/// Falls back to an unsandboxed shell when sandbox-exec is unavailable.
nonisolated enum SeatbeltSandbox {
    /// Inputs for one sandboxed invocation. Paths must be resolved absolute.
    struct Profile: Sendable {
        /// Resolved home directory, denied for reads in Project mode.
        var homePath: String
        /// Read-only roots re-allowed after the home denial (Project mode).
        var readableRoots: [String]
        /// Roots the process may write to.
        var writableRoots: [String]
        /// Whether reads under `homePath` are denied (Project mode).
        var deniesHomeReads: Bool
        /// Whether zsh skips startup files (Project mode; home is unreadable).
        var skipsShellStartupFiles: Bool
    }

    /// Hardcoded so a PATH-injected lookalike cannot replace the sandbox.
    private static let seatbeltPath = "/usr/bin/sandbox-exec"
    private static let zshPath = "/bin/zsh"

    /// Marks sandboxed child processes so tools and tests can self-check.
    static let environmentMarkerKey = "SAGE_SANDBOX"
    static let environmentMarkerValue = "seatbelt"

    /// Whether the Seatbelt executable is present on this system.
    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: seatbeltPath)
    }

    /// Maps the active PathGuard policy to sandbox inputs.
    static func profile(for policy: PathGuard.Policy, readAllowlist: [String]) -> Profile {
        switch policy {
        case .home:
            return Profile(
                homePath: PathGuard.resolvedHomePath,
                readableRoots: [],
                writableRoots: [PathGuard.resolvedHomePath],
                deniesHomeReads: false,
                skipsShellStartupFiles: false,
            )

        case .project(let root):
            let resolvedRoot = root.resolvingSymlinksInPath().path
            let readable = [resolvedRoot] + readAllowlist.map { path in
                URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            }
            return Profile(
                homePath: PathGuard.resolvedHomePath,
                readableRoots: readable,
                writableRoots: [resolvedRoot],
                deniesHomeReads: true,
                skipsShellStartupFiles: true,
            )
        }
    }

    /// SBPL text plus `-D` parameters for a profile. Split out for tests.
    static func render(
        _ profile: Profile
    ) -> (text: String, parameters: [(key: String, value: String)]) {
        // Platform defaults sit between base and the per-profile rules: the
        // dynamic HOME deny / re-allow sections that follow must outrank the
        // platform's global read allow (later rules win in SBPL).
        var sections = [SeatbeltPolicyText.base, SeatbeltPolicyText.platform]
        var parameters: [(key: String, value: String)] = []

        if profile.deniesHomeReads {
            parameters.append((key: "HOME", value: profile.homePath))
            sections.append("""
            (deny file-read* file-test-existence (subpath (param "HOME")))
            (deny file-map-executable (subpath (param "HOME")))
            """)
        }

        for (index, root) in profile.readableRoots.enumerated() {
            let key = "READABLE_ROOT_\(index)"
            parameters.append((key: key, value: root))
            sections.append(
                "(allow file-read* file-test-existence (subpath (param \"\(key)\")))"
            )
        }

        for (index, root) in profile.writableRoots.enumerated() {
            let key = "WRITABLE_ROOT_\(index)"
            parameters.append((key: key, value: root))
            sections.append("(allow file-write* (subpath (param \"\(key)\")))")
        }

        // Anchor denies stay last: no broader allow may reopen unlink/rename of
        // a writable root itself, or the policy could outlive the directory.
        for index in profile.writableRoots.indices {
            let key = "WRITABLE_ROOT_\(index)"
            sections.append(
                "(deny file-write-unlink"
                    + " (require-all (literal (param \"\(key)\")) (vnode-type DIRECTORY)))"
            )
        }

        return (sections.joined(separator: "\n"), parameters)
    }

    /// Full invocation for `command`, sandboxed via sandbox-exec when present.
    /// Paths travel as `-D` argv entries so the policy text never interpolates
    /// user-controlled data.
    static func invocation(command: String, profile: Profile) -> SeatbeltInvocation {
        let zshArguments = profile.skipsShellStartupFiles
            ? ["-f", "-c", command]
            : ["-c", command]
        guard isAvailable else {
            return SeatbeltInvocation(
                executable: URL(fileURLWithPath: zshPath),
                arguments: zshArguments,
                environment: nil,
            )
        }

        let rendered = render(profile)
        var arguments = ["-p", rendered.text]
        for parameter in rendered.parameters {
            arguments.append("-D\(parameter.key)=\(parameter.value)")
        }
        arguments.append("--")
        arguments.append(zshPath)
        arguments.append(contentsOf: zshArguments)

        var environment = ProcessInfo.processInfo.environment
        environment[environmentMarkerKey] = environmentMarkerValue
        return SeatbeltInvocation(
            executable: URL(fileURLWithPath: seatbeltPath),
            arguments: arguments,
            environment: environment,
        )
    }
}
