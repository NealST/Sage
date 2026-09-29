//
//  lib.swift
//  CodexTerminalDetection
//
//  Port of codex-rs/terminal-detection/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Detection only reads the environment. OnceLock is a lazy global.
//

import Foundation

/// Structured terminal identification data.
public struct TerminalInfo: Equatable, Sendable {
    public var name: TerminalName
    public var termProgram: String?
    public var version: String?
    public var term: String?
    public var multiplexer: Multiplexer?

    init(
        name: TerminalName,
        termProgram: String?,
        version: String?,
        term: String?,
        multiplexer: Multiplexer?
    ) {
        self.name = name
        self.termProgram = termProgram
        self.version = version
        self.term = term
        self.multiplexer = multiplexer
    }

    static func fromTermProgram(
        name: TerminalName,
        termProgram: String,
        version: String?,
        multiplexer: Multiplexer?
    ) -> TerminalInfo {
        TerminalInfo(
            name: name,
            termProgram: termProgram,
            version: version,
            term: nil,
            multiplexer: multiplexer
        )
    }

    static func fromName(
        _ name: TerminalName,
        version: String?,
        multiplexer: Multiplexer?
    ) -> TerminalInfo {
        TerminalInfo(
            name: name,
            termProgram: nil,
            version: version,
            term: nil,
            multiplexer: multiplexer
        )
    }

    static func fromTerm(_ term: String, multiplexer: Multiplexer?) -> TerminalInfo {
        let name: TerminalName
        switch term {
        case "dumb": name = .dumb
        case "xterm-ghostty": name = .ghostty
        case "wezterm", "wezterm-mux": name = .wezTerm
        default: name = .unknown
        }
        return TerminalInfo(
            name: name,
            termProgram: nil,
            version: nil,
            term: term,
            multiplexer: multiplexer
        )
    }

    static func unknown(multiplexer: Multiplexer?) -> TerminalInfo {
        TerminalInfo(
            name: .unknown,
            termProgram: nil,
            version: nil,
            term: nil,
            multiplexer: multiplexer
        )
    }

    public func userAgentToken() -> String {
        let raw: String
        if let program = termProgram {
            if let version, !version.isEmpty {
                raw = "\(program)/\(version)"
            } else {
                raw = program
            }
        } else if let term, !term.isEmpty {
            raw = term
        } else {
            switch name {
            case .appleTerminal: raw = formatTerminalVersion("Apple_Terminal", version)
            case .ghostty: raw = formatTerminalVersion("Ghostty", version)
            case .iterm2: raw = formatTerminalVersion("iTerm.app", version)
            case .warpTerminal: raw = formatTerminalVersion("WarpTerminal", version)
            case .vsCode: raw = formatTerminalVersion("vscode", version)
            case .wezTerm: raw = formatTerminalVersion("WezTerm", version)
            case .kitty: raw = "kitty"
            case .alacritty: raw = "Alacritty"
            case .konsole: raw = formatTerminalVersion("Konsole", version)
            case .gnomeTerminal: raw = "gnome-terminal"
            case .vte: raw = formatTerminalVersion("VTE", version)
            case .windowsTerminal: raw = "WindowsTerminal"
            case .dumb: raw = "dumb"
            case .unknown: raw = "unknown"
            }
        }
        return sanitizeHeaderValue(raw)
    }

    public var isZellij: Bool {
        if case .zellij = multiplexer { return true }
        return false
    }
}

public enum TerminalName: Equatable, Sendable {
    case appleTerminal
    case ghostty
    case iterm2
    case warpTerminal
    case vsCode
    case wezTerm
    case kitty
    case alacritty
    case konsole
    case gnomeTerminal
    case vte
    case windowsTerminal
    case dumb
    case unknown
}

public enum Multiplexer: Equatable, Sendable {
    case tmux(version: String?)
    case zellij(version: String?)
}

protocol TerminalEnvironment {
    func `var`(_ name: String) -> String?
    func has(_ name: String) -> Bool
    func varNonEmpty(_ name: String) -> String?
    func hasNonEmpty(_ name: String) -> Bool
}

extension TerminalEnvironment {
    func has(_ name: String) -> Bool { self.var(name) != nil }

    func varNonEmpty(_ name: String) -> String? {
        self.var(name).flatMap(noneIfWhitespace)
    }

    func hasNonEmpty(_ name: String) -> Bool {
        varNonEmpty(name) != nil
    }
}

struct ProcessEnvironment: TerminalEnvironment {
    func `var`(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name]
    }
}

private let cachedTerminalInfo: TerminalInfo = detectTerminalInfoFromEnv(ProcessEnvironment())

/// Returns a sanitized terminal identifier for User-Agent strings.
public func userAgent() -> String {
    terminalInfo().userAgentToken()
}

/// Returns structured terminal metadata for the current process.
public func terminalInfo() -> TerminalInfo {
    cachedTerminalInfo
}

func detectTerminalInfoFromEnv(_ env: any TerminalEnvironment) -> TerminalInfo {
    let multiplexer = detectMultiplexer(env)

    if let termProgram = env.varNonEmpty("TERM_PROGRAM"), !isTmuxTermProgram(termProgram) {
        let version = env.varNonEmpty("TERM_PROGRAM_VERSION")
        let name = terminalNameFromTermProgram(termProgram) ?? .unknown
        return .fromTermProgram(
            name: name,
            termProgram: termProgram,
            version: version,
            multiplexer: multiplexer
        )
    }

    if env.hasNonEmpty("GHOSTTY_RESOURCES_DIR") {
        return .fromName(.ghostty, version: nil, multiplexer: multiplexer)
    }
    if env.has("WEZTERM_VERSION") {
        return .fromName(.wezTerm, version: env.varNonEmpty("WEZTERM_VERSION"), multiplexer: multiplexer)
    }
    if env.has("ITERM_SESSION_ID") || env.has("ITERM_PROFILE") || env.has("ITERM_PROFILE_NAME") {
        return .fromName(.iterm2, version: nil, multiplexer: multiplexer)
    }
    if env.has("TERM_SESSION_ID") {
        return .fromName(.appleTerminal, version: nil, multiplexer: multiplexer)
    }
    if env.has("KITTY_WINDOW_ID") || (env.var("TERM")?.contains("kitty") == true) {
        return .fromName(.kitty, version: nil, multiplexer: multiplexer)
    }
    if env.has("ALACRITTY_SOCKET") || env.var("TERM") == "alacritty" {
        return .fromName(.alacritty, version: nil, multiplexer: multiplexer)
    }
    if env.has("KONSOLE_VERSION") {
        return .fromName(.konsole, version: env.varNonEmpty("KONSOLE_VERSION"), multiplexer: multiplexer)
    }
    if env.has("GNOME_TERMINAL_SCREEN") {
        return .fromName(.gnomeTerminal, version: nil, multiplexer: multiplexer)
    }
    if env.has("VTE_VERSION") {
        return .fromName(.vte, version: env.varNonEmpty("VTE_VERSION"), multiplexer: multiplexer)
    }
    if env.has("WT_SESSION") {
        return .fromName(.windowsTerminal, version: nil, multiplexer: multiplexer)
    }
    if let term = env.varNonEmpty("TERM") {
        return .fromTerm(term, multiplexer: multiplexer)
    }
    return .unknown(multiplexer: multiplexer)
}

func detectMultiplexer(_ env: any TerminalEnvironment) -> Multiplexer? {
    if env.hasNonEmpty("TMUX") || env.hasNonEmpty("TMUX_PANE") {
        return .tmux(version: tmuxVersionFromEnv(env))
    }
    if env.hasNonEmpty("ZELLIJ")
        || env.hasNonEmpty("ZELLIJ_SESSION_NAME")
        || env.hasNonEmpty("ZELLIJ_VERSION") {
        return .zellij(version: env.varNonEmpty("ZELLIJ_VERSION"))
    }
    return nil
}

func isTmuxTermProgram(_ value: String) -> Bool {
    value.lowercased() == "tmux"
}

func tmuxVersionFromEnv(_ env: any TerminalEnvironment) -> String? {
    guard let termProgram = env.var("TERM_PROGRAM"), isTmuxTermProgram(termProgram) else {
        return nil
    }
    return env.varNonEmpty("TERM_PROGRAM_VERSION")
}

func sanitizeHeaderValue(_ value: String) -> String {
    String(value.map { isValidHeaderValueChar($0) ? $0 : "_" })
}

func isValidHeaderValueChar(_ c: Character) -> Bool {
    c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." || c == "/")
}

func terminalNameFromTermProgram(_ value: String) -> TerminalName? {
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .filter { ![" ", "-", "_", "."].contains($0) }
        .lowercased()
    switch normalized {
    case "appleterminal": return .appleTerminal
    case "ghostty": return .ghostty
    case "iterm", "iterm2", "itermapp": return .iterm2
    case "warp", "warpterminal": return .warpTerminal
    case "vscode": return .vsCode
    case "wezterm": return .wezTerm
    case "kitty": return .kitty
    case "alacritty": return .alacritty
    case "konsole": return .konsole
    case "gnometerminal": return .gnomeTerminal
    case "vte": return .vte
    case "windowsterminal": return .windowsTerminal
    case "dumb": return .dumb
    default: return nil
    }
}

func formatTerminalVersion(_ name: String, _ version: String?) -> String {
    if let version, !version.isEmpty {
        return "\(name)/\(version)"
    }
    return name
}

func noneIfWhitespace(_ value: String) -> String? {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
}

/// Test helper: detect from an explicit environment map.
public func detectTerminalInfo(from environment: [String: String]) -> TerminalInfo {
    struct MapEnvironment: TerminalEnvironment {
        let values: [String: String]
        func `var`(_ name: String) -> String? { values[name] }
    }
    return detectTerminalInfoFromEnv(MapEnvironment(values: environment))
}
