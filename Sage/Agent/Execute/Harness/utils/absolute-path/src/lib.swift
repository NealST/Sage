//
//  lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/absolute-path/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  macOS-only port: `normalize_path_for_platform` and the Windows branches of
//  `maybe_expand_home_directory` are `cfg!(windows)`-gated upstream and are
//  excluded per plan §2.3. `dunce::canonicalize` is plain `fs::canonicalize`
//  off Windows, so `realpath(3)` stands in for both.
//
//  Rust `PathBuf` maps to a normalized `String` (see absolutize.swift).
//  `dirs::home_dir` maps to `$HOME` ?? `NSHomeDirectory()`.
//
//  The deserialization base path lives in thread-local storage exactly like
//  upstream: deserialization must stay single-threaded on the thread that
//  created the guard (Swift tasks may hop threads — same caveat applies).
//
//  `schemars`/`ts_rs` derives carry no runtime semantics and are not ported.
//

import Foundation

/// A path that is guaranteed to be absolute and normalized (though it is not
/// guaranteed to be canonicalized or exist on the filesystem).
///
/// IMPORTANT: When decoding an `AbsolutePathBuf`, a base path must be set
/// using `AbsolutePathBufGuard(basePath:)`. If no base path is set, decoding
/// fails unless the path being decoded is already absolute.
public struct AbsolutePathBuf: Hashable, Sendable {
    /// `Deref<Target = Path>` / `as_path` / `to_path_buf` / `into_path_buf`.
    public let path: String

    /// Bypasses normalization; callers must uphold the absolute+normalized
    /// invariant (mirrors the private tuple-struct constructor upstream).
    init(unchecked path: String) {
        self.path = path
    }

    private static func maybeExpandHomeDirectory(_ path: String) -> String {
        guard path.hasPrefix("~"),
              let home = AbsolutePathBufGuard.homeDirectory() else {
            return path
        }
        let rest = path.dropFirst()
        if rest.isEmpty {
            return home
        }
        if rest.hasPrefix("/") {
            return home + "/" + rest.drop(while: { $0 == "/" })
        }
        return path
    }

    /// `resolve_path_against_base`.
    public static func resolvePathAgainstBase(_ path: String, basePath: String) -> AbsolutePathBuf {
        let expanded = maybeExpandHomeDirectory(path)
        return AbsolutePathBuf(unchecked: absolutizeFrom(expanded, basePath: basePath))
    }

    /// `from_absolute_path`.
    public static func fromAbsolutePath(_ path: String) throws -> AbsolutePathBuf {
        let expanded = maybeExpandHomeDirectory(path)
        return AbsolutePathBuf(unchecked: try absolutize(expanded))
    }

    /// `from_absolute_path_checked`.
    public static func fromAbsolutePathChecked(_ path: String) throws -> AbsolutePathBuf {
        let expanded = maybeExpandHomeDirectory(path)
        guard isAbsoluteUnixPath(expanded) else {
            throw IOError.invalidInput("path is not absolute: \(path)")
        }
        return AbsolutePathBuf(unchecked: absolutizeFrom(expanded, basePath: "/"))
    }

    /// `current_dir`.
    public static func currentDir() throws -> AbsolutePathBuf {
        try fromAbsolutePath(FileManager.default.currentDirectoryPath)
    }

    /// Construct an absolute path from `path`, resolving relative paths against
    /// the process current working directory (`relative_to_current_dir`).
    public static func relativeToCurrentDir(_ path: String) throws -> AbsolutePathBuf {
        resolvePathAgainstBase(path, basePath: FileManager.default.currentDirectoryPath)
    }

    /// `join`.
    public func join(_ path: String) -> AbsolutePathBuf {
        AbsolutePathBuf.resolvePathAgainstBase(path, basePath: self.path)
    }

    /// `canonicalize` (`dunce::canonicalize` == `fs::canonicalize` on macOS).
    public func canonicalize() throws -> AbsolutePathBuf {
        AbsolutePathBuf(unchecked: try realpathString(path))
    }

    /// `parent`.
    public var parent: AbsolutePathBuf? {
        // Paths are normalized: no trailing slash, no `.`/`..` segments.
        guard let slash = path.lastIndex(of: "/") else { return nil }
        if slash == path.startIndex {
            return path.count == 1 ? nil : AbsolutePathBuf(unchecked: "/")
        }
        return AbsolutePathBuf(unchecked: String(path[..<slash]))
    }

    /// `ancestors` (includes `self`, like `Path::ancestors`).
    public func ancestors() -> [AbsolutePathBuf] {
        var result = [self]
        var current = self
        while let parent = current.parent {
            result.append(parent)
            current = parent
        }
        return result
    }

    /// `as_path`.
    public var asPath: String {
        path
    }

    /// `to_string_lossy` / `display` (paths are UTF-8 strings here).
    public var toStringLossy: String {
        path
    }

    /// `display`.
    public var display: String {
        path
    }
}

extension AbsolutePathBuf: Comparable {
    /// `PathBuf`'s derived `Ord`: lexicographic over components.
    public static func < (lhs: AbsolutePathBuf, rhs: AbsolutePathBuf) -> Bool {
        let l = unixPathComponents(lhs.path)
        let r = unixPathComponents(rhs.path)
        for (a, b) in zip(l, r) where a != b {
            return a < b
        }
        return l.count < r.count
    }
}

extension AbsolutePathBuf: CustomStringConvertible {
    public var description: String {
        path
    }
}

extension AbsolutePathBuf: Codable {
    // `PathBuf` serde: wire format is the path string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let path = try container.decode(String.self)
        if let base = try AbsolutePathBufGuard.deserializationBase(path) {
            self = AbsolutePathBuf.resolvePathAgainstBase(path, basePath: base)
        } else {
            self = try AbsolutePathBuf.fromAbsolutePath(path)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}

/// `normalize_windows_device_path` — public upstream and host-independent
/// pure string logic, so it is ported even though Sage never passes Windows
/// paths through it.
public func normalizeWindowsDevicePath(_ path: String) -> String? {
    if let unc = path.stripPrefix(#"\\?\UNC\"#) {
        return #"\\"# + unc
    }
    if let unc = path.stripPrefix(#"\\.\UNC\"#) {
        return #"\\"# + unc
    }
    if let rest = path.stripPrefix(#"\\?\"#), isWindowsDriveAbsolutePath(rest) {
        return rest
    }
    if let rest = path.stripPrefix(#"\\.\"#), isWindowsDriveAbsolutePath(rest) {
        return rest
    }
    return nil
}

private func isWindowsDriveAbsolutePath(_ path: String) -> Bool {
    let bytes = path.utf8
    guard bytes.count >= 3 else { return false }
    let b = Array(bytes.prefix(3))
    return (b[0] >= 65 && b[0] <= 90) || (b[0] >= 97 && b[0] <= 122)
        ? b[1] == 58 && (b[2] == 92 || b[2] == 47)
        : false
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

/// `canonicalize_preserving_symlinks`.
///
/// Top-level system aliases such as macOS `/var -> /private/var` still remain
/// canonicalized; nested symlinks keep the logical path.
public func canonicalizePreservingSymlinks(_ path: String) throws -> String {
    let logical = try AbsolutePathBuf.fromAbsolutePath(path).path
    let preserveLogicalPath = shouldPreserveLogicalPath(logical)
    if let canonical = try? realpathString(path) {
        return preserveLogicalPath && canonical != logical ? logical : canonical
    }
    return logical
}

/// `canonicalize_existing_preserving_symlinks` — unlike
/// `canonicalizePreservingSymlinks`, canonicalization failures propagate.
public func canonicalizeExistingPreservingSymlinks(_ path: String) throws -> String {
    let logical = try AbsolutePathBuf.fromAbsolutePath(path).path
    let canonical = try realpathString(path)
    return shouldPreserveLogicalPath(logical) && canonical != logical ? logical : canonical
}

private func shouldPreserveLogicalPath(_ logical: String) -> Bool {
    AbsolutePathBuf(unchecked: logical).ancestors().contains { ancestor in
        // `ancestor.parent().and_then(Path::parent).is_some()`: only nested
        // (deeper than top-level) symlinks preserve the logical path.
        guard let parent = ancestor.parent, parent.parent != nil else { return false }
        return isSymlink(ancestor.path)
    }
}

private func isSymlink(_ path: String) -> Bool {
    var st = stat()
    guard lstat(path, &st) == 0 else { return false }
    return (st.st_mode & S_IFMT) == S_IFLNK
}

/// `fs::canonicalize` via `realpath(3)`: fails when the path does not exist.
func realpathString(_ path: String) throws -> String {
    guard let resolved = Darwin.realpath(path, nil) else {
        throw IOError.fromErrno(errno, context: "canonicalize failed: \(path)")
    }
    defer { free(resolved) }
    return String(cString: resolved)
}

// MARK: - AbsolutePathBufGuard

/// `std::io::Error` from `AbsolutePathBufGuard::deserialization_base`.
public struct AbsolutePathDeserializationError: Error, Equatable {
    public let message: String
}

/// Ensure this guard is held while decoding `AbsolutePathBuf` values to
/// provide a base path for resolving relative paths. Because this relies on
/// thread-local storage, the deserialization must be single-threaded and
/// occur on the same thread that created the guard.
private let absolutePathBaseKey = "codex.utils.absolute-path.base"
private let absolutePathHomeKey = "codex.utils.absolute-path.home"

public final class AbsolutePathBufGuard {

    /// `AbsolutePathBufGuard::deserialization_base` — reads the native
    /// deserialization base and validates the guard requirement before home
    /// expansion or namespace normalization. Does not look up cwd.
    public static func deserializationBase(_ path: String) throws -> String? {
        let base = Thread.current.threadDictionary[absolutePathBaseKey] as? String
        if base == nil && !isAbsoluteUnixPath(path) {
            throw AbsolutePathDeserializationError(
                message: "AbsolutePathBuf deserialized without a base path"
            )
        }
        return base
    }

    /// `AbsolutePathBufGuard::home_directory` — thread-local override first,
    /// then the native home (`dirs::home_dir` ≈ `$HOME` ?? `NSHomeDirectory()`).
    public static func homeDirectory() -> String? {
        if let override = Thread.current.threadDictionary[absolutePathHomeKey] as? String {
            return override
        }
        return ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    /// `AbsolutePathBufGuard::new`.
    public init(basePath: String) {
        Thread.current.threadDictionary[absolutePathBaseKey] = basePath
    }

    /// `AbsolutePathBufGuard::with_home_directory` — resolves home-relative
    /// paths against `homeDirectory` during `operation`. The operation must
    /// complete synchronously on the current thread.
    public static func withHomeDirectory<T>(
        _ homeDirectory: String,
        operation: () throws -> T
    ) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        let previousHome = dictionary[absolutePathHomeKey]
        dictionary[absolutePathHomeKey] = homeDirectory
        defer {
            if let previousHome {
                dictionary[absolutePathHomeKey] = previousHome
            } else {
                dictionary.removeObject(forKey: absolutePathHomeKey)
            }
        }
        return try operation()
    }

    deinit {
        Thread.current.threadDictionary.removeObject(forKey: absolutePathBaseKey)
    }
}

// MARK: - test_support

/// `pub mod test_support` — helpers for constructing absolute paths in tests.
public enum AbsolutePathTestSupport {
    /// `test_path_buf` — on macOS a Unix-style absolute path is already native.
    public static func testPathBuf(_ unixPath: String) -> String {
        unixPath
    }

    /// `PathExt::abs` — converts an already absolute path into an
    /// `AbsolutePathBuf` (`expect("path should already be absolute")`).
    public static func abs(_ path: String) -> AbsolutePathBuf {
        do {
            return try AbsolutePathBuf.fromAbsolutePathChecked(path)
        } catch {
            fatalError("path should already be absolute: \(path)")
        }
    }
}
