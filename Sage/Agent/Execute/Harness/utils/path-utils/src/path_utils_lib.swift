//
//  path_utils_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-utils/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  macOS-only port (plan §2.3):
//  - `normalize_for_native_workdir`'s `cfg!(windows)` branch uses
//    `dunce::simplified`; ported as an approximation (`dunceSimplified`)
//    since the flag is always false on macOS.
//  - The WSL helpers (`is_wsl_case_insensitive_path`, `lower_ascii_path`,
//    `ascii_eq_ignore_case`) are `cfg(target_os = "linux")`-gated upstream and
//    kept under `#if os(Linux)`.
//
//  Rust `PathBuf` maps to `String`; `Path` equality (component-based) maps to
//  `rustPathEqual`. `dunce::canonicalize` is plain `fs::canonicalize` off
//  Windows, so `realpathString` stands in for both. `tempfile::NamedTempFile`
//  maps to a sibling temp file + `rename(2)`.
//
//  R4a: upstream `lib.rs` maps to `path_utils_lib.swift` because
//  `utils/absolute-path/src/lib.swift` claimed the basename first (plan §5.1).
//

import Foundation

/// `Path` equality: lexicographic over `components()` — repeated separators
/// ignored, `.` normalized away except a leading `.` on a relative path.
func rustPathComponents(_ path: String) -> [String] {
    var result: [String] = []
    var rest = Substring(path)
    if rest.hasPrefix("/") {
        result.append("/") // RootDir
        rest = rest.dropFirst()
    }
    var isFirstComponent = true
    let hasRoot = !result.isEmpty
    for part in rest.split(separator: "/", omittingEmptySubsequences: true) {
        if part == "." && !(isFirstComponent && !hasRoot) {
            isFirstComponent = false
            continue
        }
        result.append(String(part))
        isFirstComponent = false
    }
    return result
}

func rustPathEqual(_ left: String, _ right: String) -> Bool {
    rustPathComponents(left) == rustPathComponents(right)
}

public func normalizeForPathComparison(_ path: String) throws -> String {
    let canonical = try realpathString(path)
    return normalizeForWsl(canonical)
}

/// Compare paths after applying Codex's filesystem normalization.
///
/// If either path cannot be normalized, this falls back to direct path
/// equality.
public func pathsMatchAfterNormalization(_ left: String, _ right: String) -> Bool {
    if let left = try? normalizeForPathComparison(left),
       let right = try? normalizeForPathComparison(right) {
        return left == right
    }
    return rustPathEqual(left, right)
}

/// Replace paths equal to `oldPath` and remove duplicates, preserving their
/// order.
///
/// Other paths, including descendants of `oldPath`, remain unchanged. This
/// uses path equality without filesystem access or normalization; callers
/// validate paths.
public func replacePathAndDeduplicate(
    _ paths: [String],
    oldPath: String,
    newPath: String
) -> [String] {
    let replaced = paths.map { rustPathEqual($0, oldPath) ? newPath : $0 }
    // `HashSet<P: AsRef<Path>>` dedups by `Path`'s component-based equality.
    var seen = Set<[String]>()
    return replaced.filter { seen.insert(rustPathComponents($0)).inserted }
}

public func normalizeForNativeWorkdir(_ path: String) -> String {
    normalizeForNativeWorkdirWithFlag(path, isWindows: false)
}

/// `normalize_for_native_workdir_with_flag`. The `isWindows: true` branch is
/// an approximation of `dunce::simplified` (Windows-only upstream, §2.3).
func normalizeForNativeWorkdirWithFlag(_ path: String, isWindows: Bool) -> String {
    isWindows ? dunceSimplified(path) : path
}

/// `dunce::simplified` (approximation): strip a `\\?\` verbatim prefix when
/// the remainder is a drive-absolute path without `..` components.
private func dunceSimplified(_ path: String) -> String {
    guard path.hasPrefix(#"\\?\"#) else { return path }
    let rest = String(path.dropFirst(4))
    let bytes = rest.utf8
    guard bytes.count >= 3 else { return path }
    let b = Array(bytes.prefix(3))
    let isDrive = (b[0] >= 65 && b[0] <= 90) || (b[0] >= 97 && b[0] <= 122)
    guard isDrive, b[1] == 58, b[2] == 92 || b[2] == 47 else { return path }
    let hasDotDot = rest.split(separator: "\\").contains("..")
    return hasDotDot ? path : rest
}

public struct SymlinkWritePaths: Equatable {
    public let readPath: String?
    public let writePath: String
}

/// Resolve the final filesystem target for `path` while retaining a safe
/// write path.
///
/// This follows symlink chains (including relative symlink targets) until it
/// reaches a non-symlink path. If the chain cycles or any metadata/link
/// resolution fails, it returns `readPath: nil` and uses the original
/// absolute path as `writePath`. There is no fixed max-resolution count;
/// cycles are detected via a visited set.
public func resolveSymlinkWritePaths(_ path: String) throws -> SymlinkWritePaths {
    let root = (try? AbsolutePathBuf.fromAbsolutePath(path).path) ?? path
    var current = root
    var visited = Set<String>()

    // Follow symlink chains while guarding against cycles.
    while true {
        var statBuffer = Darwin.stat()
        if lstat(current, &statBuffer) != 0 {
            if errno == ENOENT {
                return SymlinkWritePaths(readPath: current, writePath: current)
            }
            return SymlinkWritePaths(readPath: nil, writePath: root)
        }

        if statBuffer.st_mode & S_IFMT != S_IFLNK {
            return SymlinkWritePaths(readPath: current, writePath: current)
        }

        // If we've already seen this path, the chain cycles.
        if !visited.insert(current).inserted {
            return SymlinkWritePaths(readPath: nil, writePath: root)
        }

        let target: String
        do {
            target = try FileManager.default.destinationOfSymbolicLink(atPath: current)
        } catch {
            return SymlinkWritePaths(readPath: nil, writePath: root)
        }

        if target.hasPrefix("/") {
            guard let absolute = try? AbsolutePathBuf.fromAbsolutePath(target) else {
                return SymlinkWritePaths(readPath: nil, writePath: root)
            }
            current = absolute.path
        } else if let parent = AbsolutePathBuf(unchecked: current).parent {
            current = AbsolutePathBuf.resolvePathAgainstBase(target, basePath: parent.path).path
        } else {
            return SymlinkWritePaths(readPath: nil, writePath: root)
        }
    }
}

public func writeAtomically(writePath: String, contents: String) throws {
    guard let parent = rustParentPath(writePath) else {
        throw IOError.invalidInput("path \(writePath) has no parent directory")
    }
    if !parent.isEmpty {
        try FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: true
        )
    }
    let tempPath = parent.isEmpty
        ? ".codex-atomic-" + UUID().uuidString
        : parent + "/.codex-atomic-" + UUID().uuidString
    do {
        try contents.write(toFile: tempPath, atomically: false, encoding: .utf8)
    } catch {
        try? FileManager.default.removeItem(atPath: tempPath)
        throw error
    }
    // `NamedTempFile::persist` is `rename(2)` on Unix.
    if Darwin.rename(tempPath, writePath) != 0 {
        let renameErrno = errno
        try? FileManager.default.removeItem(atPath: tempPath)
        throw IOError.fromErrno(renameErrno, context: "persist failed: \(writePath)")
    }
}

/// `Path::parent` (Unix): trailing slashes ignored; `"foo"` → `""`;
/// `"/"` and `""` → `nil`.
private func rustParentPath(_ path: String) -> String? {
    if path.isEmpty { return nil }
    var trimmed = path
    while trimmed.count > 1, trimmed.hasSuffix("/") {
        trimmed.removeLast()
    }
    guard let slash = trimmed.lastIndex(of: "/") else {
        return trimmed == "/" ? nil : ""
    }
    if slash == trimmed.startIndex {
        return trimmed.count == 1 ? nil : "/"
    }
    return String(trimmed[..<slash])
}

func normalizeForWsl(_ path: String) -> String {
    normalizeForWslWithFlag(path, isWsl: isWsl())
}

func normalizeForWslWithFlag(_ path: String, isWsl: Bool) -> String {
    guard isWsl else { return path }
    guard isWslCaseInsensitivePath(path) else { return path }
    return lowerAsciiPath(path)
}

func isWslCaseInsensitivePath(_ path: String) -> Bool {
    #if os(Linux)
        // RootDir, then "mnt" (ASCII case-insensitive), then a one-letter
        // drive component.
        var components = rustPathComponents(path).makeIterator()
        guard components.next() == "/",
              let mnt = components.next(),
              asciiEqualIgnoreCase(Array(mnt.utf8), Array("mnt".utf8)),
              let drive = components.next() else {
            return false
        }
        let driveBytes = Array(drive.utf8)
        return driveBytes.count == 1
            && (driveBytes[0] >= 65 && driveBytes[0] <= 90
                || driveBytes[0] >= 97 && driveBytes[0] <= 122)
    #else
        return false
    #endif
}

#if os(Linux)
    func asciiEqualIgnoreCase(_ left: [UInt8], _ right: [UInt8]) -> Bool {
        left.count == right.count
            && zip(left, right).allSatisfy { lhs, rhs in
                asciiLowercase(lhs) == rhs
            }
    }

    func lowerAsciiPath(_ path: String) -> String {
        // WSL mounts Windows drives under /mnt/<drive>, which are
        // case-insensitive.
        String(decoding: path.utf8.map(asciiLowercase), as: UTF8.self)
    }

    private func asciiLowercase(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte + 32 : byte
    }
#else
    func lowerAsciiPath(_ path: String) -> String {
        path
    }
#endif
