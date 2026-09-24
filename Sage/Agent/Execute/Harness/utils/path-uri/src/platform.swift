//
//  platform.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-uri/src/platform.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Platform identity and its path convention, independent of the resolving
//  host.
//

import Foundation

/// Operating system whose paths and execution configuration are being
/// resolved (`Platform`).
public enum Platform: Equatable, Hashable, Sendable {
    case linux
    case macos
    case windows
    /// Missing or unrecognized platform metadata carries no path convention.
    case unknown

    /// Read platform metadata without substituting the current host's
    /// platform (`from_platform_os`).
    public static func fromPlatformOs(_ platformOs: String?) -> Platform {
        switch platformOs {
        case "linux": return .linux
        case "macos": return .macos
        case "windows": return .windows
        default: return .unknown
        }
    }

    /// Return the platform of the current process (`native()`).
    public static func native() -> Platform {
        #if os(Linux)
        return .linux
        #elseif os(macOS)
        return .macos
        #elseif os(Windows)
        return .windows
        #else
        return .unknown
        #endif
    }

    /// Derive path grammar from platform identity while preserving unknown
    /// metadata (`path_convention`).
    public func pathConvention() -> PathConvention? {
        switch self {
        case .linux, .macos: return .posix
        case .windows: return .windows
        case .unknown: return nil
        }
    }
}
