//
//  absolutize.swift
//  CodexUtils
//
//  Port of codex-rs/utils/absolute-path/src/absolutize.rs (Apache-2.0;
//  adapted from path-absolutize 3.1.1, MIT, (c) 2018 magiclen.org (Ron Li)).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  macOS-only port: the `#[cfg(windows)] path_with_base` branch (drive
//  prefixes, root-relative paths) is excluded per plan §2.3.
//
//  Rust `Path`/`PathBuf` map to `String` with Unix component semantics
//  (`unixPathComponents` mirrors `Path::components`: repeated separators are
//  ignored and `.` is normalized away except at the start of a relative path).
//

import Foundation

/// `std::path::Component` (Unix subset; Windows `Prefix` never occurs).
enum UnixPathComponent: Equatable {
    case rootDir
    case curDir
    case parentDir
    case normal(String)

    /// Ordering rank matching the derived `Ord` on `Component`.
    var rank: Int {
        switch self {
        case .rootDir: return 0
        case .curDir: return 1
        case .parentDir: return 2
        case .normal: return 3
        }
    }
}

extension UnixPathComponent: Comparable {
    static func < (lhs: UnixPathComponent, rhs: UnixPathComponent) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        switch (lhs, rhs) {
        case (.normal(let a), .normal(let b)):
            // OsStr byte ordering on Unix.
            return a.utf8.lexicographicallyPrecedes(b.utf8)
        default:
            return false
        }
    }
}

/// `Path::components` (Unix).
func unixPathComponents(_ path: String) -> [UnixPathComponent] {
    var components: [UnixPathComponent] = []
    if path.hasPrefix("/") {
        components.append(.rootDir)
    }
    for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
        switch segment {
        case ".":
            // `.` is preserved only at the start of a relative path.
            if components.isEmpty {
                components.append(.curDir)
            }
        case "..":
            components.append(.parentDir)
        default:
            components.append(.normal(String(segment)))
        }
    }
    return components
}

func isAbsoluteUnixPath(_ path: String) -> Bool {
    path.hasPrefix("/")
}

/// `normalize_path` — lexically resolve `.`/`..` without touching the fs.
/// `PathBuf::pop` on an empty or root path is a no-op, which this reproduces.
func normalizePath(_ path: String) -> String {
    var rooted = false
    var stack: [String] = []
    for component in unixPathComponents(path) {
        switch component {
        case .rootDir:
            rooted = true
        case .curDir:
            break
        case .parentDir:
            if !stack.isEmpty {
                stack.removeLast()
            }
        case .normal(let name):
            stack.append(name)
        }
    }
    let joined = stack.joined(separator: "/")
    if rooted {
        return "/" + joined
    }
    return joined.isEmpty ? "." : joined
}

/// `path_with_base` (Unix branch).
func pathWithBase(_ path: String, base: String) -> String {
    if isAbsoluteUnixPath(path) {
        return path
    }
    if base.isEmpty {
        return path
    }
    if base.hasSuffix("/") {
        return base + path
    }
    return base + "/" + path
}

/// `absolutize` — only the current-working-directory lookup is fallible.
func absolutize(_ path: String) throws -> String {
    if isAbsoluteUnixPath(path) {
        return normalizePath(path)
    }
    return absolutizeFrom(path, basePath: FileManager.default.currentDirectoryPath)
}

/// `absolutize_from`.
func absolutizeFrom(_ path: String, basePath: String) -> String {
    normalizePath(pathWithBase(path, base: basePath))
}
