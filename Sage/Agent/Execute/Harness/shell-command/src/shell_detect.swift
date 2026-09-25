//
//  shell_detect.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_detect.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  ShellType detection and user-shell lookup. `getpwuid_r` is replaced by
//  `getpwuid_r` via Darwin libc. PowerShell/cmd detection is kept so
//  Windows-shaped argv still classifies.
//

import Foundation

public enum ShellType: String, Codable, Equatable, Sendable {
    case zsh
    case bash
    case powerShell
    case sh
    case cmd

    public func name() -> String {
        switch self {
        case .zsh: return "zsh"
        case .bash: return "bash"
        case .powerShell: return "powershell"
        case .sh: return "sh"
        case .cmd: return "cmd"
        }
    }
}

public struct DetectedShell: Equatable, Sendable {
    public var shellType: ShellType
    public var shellPath: String

    public init(shellType: ShellType, shellPath: String) {
        self.shellType = shellType
        self.shellPath = shellPath
    }

    public func name() -> String {
        shellType.name()
    }
}

public func detectShellType(_ shellPath: String) -> ShellType? {
    switch shellPath {
    case "zsh": return .zsh
    case "sh": return .sh
    case "cmd": return .cmd
    case "bash": return .bash
    case "pwsh", "powershell": return .powerShell
    default:
        let stem = (shellPath as NSString).lastPathComponent
        let stemNoExt = (stem as NSString).deletingPathExtension
        if stemNoExt != shellPath && stem != shellPath {
            return detectShellType(stemNoExt)
        }
        if stemNoExt != shellPath {
            return detectShellType(stemNoExt)
        }
        return nil
    }
}

public func getUserShellPath() -> String? {
    if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
        return shell
    }
    let uid = getuid()
    var pwd = passwd()
    var result: UnsafeMutablePointer<passwd>?
    let suggested = sysconf(_SC_GETPW_R_SIZE_MAX)
    let bufferLen = suggested > 0 ? Int(suggested) : 1024
    var buffer = [CChar](repeating: 0, count: bufferLen)
    let status = getpwuid_r(uid, &pwd, &buffer, buffer.count, &result)
    guard status == 0, result != nil, let shell = pwd.pw_shell else { return nil }
    return String(cString: shell)
}

public func detectDefaultUserShell() -> DetectedShell {
    defaultUserShell()
}

public func ultimateFallbackShell() -> DetectedShell {
    DetectedShell(shellType: .sh, shellPath: "/bin/sh")
}

public func getShell(_ shellType: ShellType) -> DetectedShell? {
    switch shellType {
    case .zsh: return shellIfPresent(type: .zsh, binary: "zsh", fallbacks: ["/bin/zsh"])
    case .bash: return shellIfPresent(type: .bash, binary: "bash", fallbacks: ["/bin/bash", "/usr/bin/bash"])
    case .sh: return shellIfPresent(type: .sh, binary: "sh", fallbacks: ["/bin/sh"])
    case .powerShell:
        return shellIfPresent(type: .powerShell, binary: "pwsh", fallbacks: ["/usr/local/bin/pwsh"])
            ?? shellIfPresent(type: .powerShell, binary: "powershell", fallbacks: [])
    case .cmd:
        return shellIfPresent(type: .cmd, binary: "cmd", fallbacks: [])
    }
}

public func getShellByModelProvidedPath(_ shellPath: String) -> DetectedShell {
    detectShellType(shellPath).flatMap(getShell) ?? ultimateFallbackShell()
}

public func defaultUserShell() -> DetectedShell {
    defaultUserShellFromPath(getUserShellPath())
}

public func defaultUserShellFromPath(_ userShellPath: String?) -> DetectedShell {
    let userDefault = userShellPath.flatMap(detectShellType).flatMap(getShell)
    return userDefault
        ?? getShell(.zsh)
        ?? getShell(.bash)
        ?? ultimateFallbackShell()
}

private func shellIfPresent(type: ShellType, binary: String, fallbacks: [String]) -> DetectedShell? {
    if let user = getUserShellPath(),
       detectShellType(user) == type,
       FileManager.default.isExecutableFile(atPath: user) {
        return DetectedShell(shellType: type, shellPath: user)
    }
    if let resolved = which(binary) {
        return DetectedShell(shellType: type, shellPath: resolved)
    }
    for fallback in fallbacks where FileManager.default.isExecutableFile(atPath: fallback) {
        return DetectedShell(shellType: type, shellPath: fallback)
    }
    return nil
}

private func which(_ binary: String) -> String? {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for directory in path.split(separator: ":") {
        let candidate = (String(directory) as NSString).appendingPathComponent(binary)
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}
