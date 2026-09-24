//
//  api_path_string.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-uri/src/api_path_string.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `Path`/`PathBuf` map to `String` (UTF-8); `String::from_utf8_lossy` maps
//  to `String(decoding:as: UTF8.self)` (U+FFFD replacement). `schemars`/
//  `ts_rs` derives are not ported.
//

import Foundation

/// A UTF-8 path for preserving raw path compatibility at the app-server API
/// boundary while Codex migrates to `PathUri` (`LegacyAppPathString`).
///
/// Deserialization and `fromString` accept any UTF-8 string without
/// interpreting or validating it. Relative path text remains valid until an
/// operation such as `toPathUri` requires an absolute path.
public struct LegacyAppPathString: Hashable, Sendable {
    private let value: String

    /// The private tuple-struct constructor upstream (crate-internal; tests
    /// use it via `@testable`).
    init(_ value: String) {
        self.value = value
    }

    /// Preserves already-legacy app-server path text without interpreting it
    /// using the current host (`from_string`).
    public static func fromString(_ path: String) -> LegacyAppPathString {
        LegacyAppPathString(path)
    }

    /// Preserves path text without interpreting it using the current host
    /// (`from_path`; `to_string_lossy` is the identity for UTF-8 strings).
    public static func fromPath(_ path: String) -> LegacyAppPathString {
        LegacyAppPathString(path)
    }

    /// Renders an absolute path using the current host's path convention
    /// (`from_abs_path`).
    public static func fromAbsPath(_ path: AbsolutePathBuf) -> LegacyAppPathString {
        fromPath(path.path)
    }

    /// Renders a path URI using the requested native path convention
    /// (`from_path_uri`). Rendering fails when the URI shape does not match
    /// the convention. Non-UTF-8 segments are rendered lossily, and encoded
    /// separators are emitted as native path text.
    public static func fromPathUri(
        _ path: PathUri,
        convention: PathConvention
    ) throws -> LegacyAppPathString {
        if let pathBytes = path.opaqueFallbackBytes() {
            return LegacyAppPathString(try renderOpaqueFallback(path, pathBytes, convention))
        }
        switch convention {
        case .posix:
            return LegacyAppPathString(try renderPosixPath(path))
        case .windows:
            return LegacyAppPathString(try renderWindowsPath(path))
        }
    }

    /// Parses this API string as an absolute path using the requested native
    /// path convention and returns its canonical path URI (`to_path_uri`).
    public func toPathUri(_ convention: PathConvention) throws -> PathUri {
        guard let uri = PathUri.fromAbsoluteNativePath(value, convention: convention) else {
            throw LegacyAppPathStringError.invalidNativePath(path: value, convention: convention)
        }
        return uri
    }

    /// Resolves this raw API path spelling against an executor cwd
    /// (`resolve_against`). Relative paths use the cwd's inferred convention.
    /// Home-relative paths use the supplied executor home, and clearly
    /// foreign absolute paths are rejected rather than reinterpreted as
    /// relative path text.
    public func resolveAgainst(cwd: PathUri, userHomeDir: PathUri?) throws -> PathUri {
        guard let convention = cwd.inferPathConvention() else {
            throw LegacyAppPathStringError.missingBaseConvention(cwd: cwd.description)
        }
        let isWindows = convention == .windows
        if let suffix = convention.homeRelativeSuffix(value) {
            guard let home = userHomeDir else {
                throw LegacyAppPathStringError.missingHomeDirectory(path: value)
            }
            let trimmed = suffix.drop(while: { $0 == "/" || (isWindows && $0 == "\\") })
            do {
                return try home.join(String(trimmed))
            } catch let error as PathUriParseError {
                throw LegacyAppPathStringError.pathUri(error)
            }
        }

        if isWindows && (value.hasPrefix("//") || value.hasPrefix(#"\\"#)) {
            return try toPathUri(.windows)
        }

        if let pathConvention = inferAbsolutePathConvention() {
            if pathConvention == convention {
                return try toPathUri(convention)
            }
            if pathConvention == .posix && isWindows {
                do {
                    return try cwd.join(value)
                } catch let error as PathUriParseError {
                    throw LegacyAppPathStringError.pathUri(error)
                }
            }
            throw LegacyAppPathStringError.mismatchedConvention(
                path: value,
                pathConvention: pathConvention,
                cwd: cwd.description,
                convention: convention
            )
        }
        do {
            return try cwd.join(value)
        } catch let error as PathUriParseError {
            throw LegacyAppPathStringError.pathUri(error)
        }
    }

    /// Parses this API string as an absolute path using the convention
    /// inferred from its spelling (`to_inferred_path_uri`).
    public func toInferredPathUri() -> PathUri? {
        try? PathUri(fromLegacy: self)
    }

    /// Renders this API path for display in a user interface
    /// (`render_for_ui`). Strings that cannot be interpreted as absolute
    /// paths retain their raw API spelling.
    public func renderForUi() -> String {
        toInferredPathUri()?.inferredNativePathString() ?? value
    }

    /// Parses this API string as a host-native absolute path
    /// (`to_inferred_abs_path`).
    public func toInferredAbsPath() -> AbsolutePathBuf? {
        try? AbsolutePathBuf(fromLegacy: self)
    }

    /// Infers the path convention of an absolute API path from its spelling
    /// (`infer_absolute_path_convention`). Relative paths and ambiguous
    /// spellings return nil. Slash-prefixed paths are treated as POSIX even
    /// when they could also be interpreted as slash-delimited Windows UNC
    /// paths.
    public func inferAbsolutePathConvention() -> PathConvention? {
        let bytes = Array(value.utf8)
        let hasWindowsDriveRoot = bytes.count >= 3
            && isAsciiAlpha(bytes[0])
            && bytes[1] == UInt8(ascii: ":")
            && isWindowsSeparatorByte(bytes[2])
        if hasWindowsDriveRoot || value.hasPrefix(#"\\"#) {
            return .windows
        }
        if value.hasPrefix("/") {
            return .posix
        }
        return nil
    }

    public func asStr() -> String {
        value
    }

    public func intoString() -> String {
        value
    }
}

extension LegacyAppPathString: CustomStringConvertible {
    public var description: String {
        value
    }
}

extension LegacyAppPathString: Codable {
    /// `#[serde(transparent)]`: the wire format is the raw string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// `From<AbsolutePathBuf> for LegacyAppPathString`.
extension LegacyAppPathString {
    public init(_ path: AbsolutePathBuf) {
        self = .fromAbsPath(path)
    }

    /// `From<PathUri> for LegacyAppPathString`.
    public init(_ path: PathUri) {
        self.init(path.inferredNativePathString())
    }
}

/// `TryFrom<LegacyAppPathString> for PathUri`.
extension PathUri {
    public init(fromLegacy path: LegacyAppPathString) throws {
        guard let convention = path.inferAbsolutePathConvention() else {
            throw LegacyAppPathStringError.invalidNativePath(path: path.asStr(), convention: nil)
        }
        guard let uri = PathUri.fromAbsoluteNativePath(path.asStr(), convention: convention) else {
            throw LegacyAppPathStringError.invalidNativePath(
                path: path.asStr(),
                convention: convention
            )
        }
        self = uri
    }
}

/// `TryFrom<LegacyAppPathString> for AbsolutePathBuf`.
extension AbsolutePathBuf {
    public init(fromLegacy path: LegacyAppPathString) throws {
        do {
            self = try AbsolutePathBuf.fromAbsolutePathChecked(path.asStr())
        } catch {
            throw LegacyAppPathStringError.invalidNativePath(path: path.asStr(), convention: nil)
        }
    }
}

/// `render_opaque_fallback`.
private func renderOpaqueFallback(
    _ path: PathUri,
    _ pathBytes: [UInt8],
    _ convention: PathConvention
) throws -> String {
    let rendered: String?
    switch convention {
    case .posix where pathBytes.first == UInt8(ascii: "/"):
        rendered = String(decoding: pathBytes, as: UTF8.self)
    case .windows:
        rendered = renderWindowsOpaqueFallback(pathBytes)
    case .posix:
        rendered = nil
    }
    guard let rendered else {
        throw LegacyAppPathStringError.opaqueFallback(path: path.description)
    }
    return rendered
}

/// `render_windows_opaque_fallback`.
private func renderWindowsOpaqueFallback(_ pathBytes: [UInt8]) -> String? {
    guard pathBytes.count % 2 == 0 else {
        return nil
    }
    let pathWide = stride(from: 0, to: pathBytes.count, by: 2)
        .map { UInt16(pathBytes[$0]) | UInt16(pathBytes[$0 + 1]) << 8 }

    // Windows absolute paths either have a rooted drive prefix (`C:\`) or a
    // rooted namespace/UNC prefix (`\\server`, `\\.\`, or `\\?\`).
    let isSeparator: (UInt16) -> Bool = {
        $0 == UInt16(UnicodeScalar("\\").value) || $0 == UInt16(UnicodeScalar("/").value)
    }
    let hasDriveRoot: Bool = {
        guard pathWide.count >= 3 else { return false }
        let drive = pathWide[0]
        let isAlpha = (UInt16(UnicodeScalar("A").value)...UInt16(UnicodeScalar("Z").value))
            .contains(drive)
            || (UInt16(UnicodeScalar("a").value)...UInt16(UnicodeScalar("z").value))
            .contains(drive)
        return isAlpha && pathWide[1] == UInt16(UnicodeScalar(":").value)
            && isSeparator(pathWide[2])
    }()
    let hasNamespaceOrUncRoot = pathWide.count >= 2
        && isSeparator(pathWide[0]) && isSeparator(pathWide[1])
    guard hasDriveRoot || hasNamespaceOrUncRoot else {
        return nil
    }
    return String(decoding: pathWide, as: UTF16.self)
}

/// `render_posix_path`.
private func renderPosixPath(_ path: PathUri) throws -> String {
    let url = path.toUrl()
    // POSIX file paths do not have a UNC authority, so `file://server/share`
    // cannot be represented as `/share` without losing the server identity.
    guard url.hostStr == nil else {
        throw incompatibleConvention(path, .posix)
    }

    // URI segments are already separated with `/` on every host. Decode each
    // one independently so `file:///a%20dir/file` becomes `/a dir/file`.
    var rendered = ""
    for segment in url.pathSegments {
        rendered.append("/")
        rendered.append(decodeNativeSegment(segment))
    }
    return rendered
}

/// `render_windows_path`.
private func renderWindowsPath(_ path: PathUri) throws -> String {
    let url = path.toUrl()
    var segments = url.pathSegments[...]
    var rendered = ""
    if let host = url.hostStr {
        // A URI authority selects the UNC form: `file://server/share/file`
        // becomes `\\server\share\file`. The first segment is the share name,
        // which must be present.
        guard let shareSegment = segments.popFirst() else {
            throw incompatibleConvention(path, .windows)
        }
        let share = decodeNativeSegment(shareSegment)
        if share.isEmpty {
            throw incompatibleConvention(path, .windows)
        }
        rendered.append(#"\\"#)
        rendered.append(host)
        rendered.append("\\")
        rendered.append(share)
    } else {
        // Without an authority, Windows requires a drive root. For example,
        // `file:///C:/src/main.rs` begins with the `C:` URI segment and
        // renders as `C:\src\main.rs`; a POSIX URI such as `file:///usr/bin`
        // is rejected.
        guard let driveSegment = segments.popFirst() else {
            throw incompatibleConvention(path, .windows)
        }
        let drive = decodeNativeSegment(driveSegment)
        let bytes = Array(drive.utf8)
        guard bytes.count == 2, isAsciiAlpha(bytes[0]), bytes[1] == UInt8(ascii: ":") else {
            throw incompatibleConvention(path, .windows)
        }
        rendered.append(drive)
    }

    for segment in segments {
        // URL path separators become Windows separators after each component
        // has been decoded.
        rendered.append("\\")
        rendered.append(decodeNativeSegment(segment))
    }
    // `file:///C:` and `file:///C:/` both identify the drive root, never the
    // drive-relative path `C:`.
    let renderedBytes = Array(rendered.utf8)
    if renderedBytes.count == 2 && renderedBytes[1] == UInt8(ascii: ":") {
        rendered.append("\\")
    }
    return rendered
}

/// `decode_native_segment`: decode exactly once, so `%252F` becomes the
/// literal text `%2F` rather than being decoded a second time into `/`.
private func decodeNativeSegment(_ segment: String) -> String {
    String(decoding: urlDecodeBinary(Array(segment.utf8)), as: UTF8.self)
}

/// `incompatible_convention`.
private func incompatibleConvention(
    _ path: PathUri,
    _ convention: PathConvention
) -> LegacyAppPathStringError {
    .incompatibleConvention(path: path.description, convention: convention)
}

// MARK: - LegacyAppPathStringError

/// `LegacyAppPathStringError`.
public enum LegacyAppPathStringError: Error, Equatable, CustomStringConvertible {
    case opaqueFallback(path: String)
    case incompatibleConvention(path: String, convention: PathConvention)
    case invalidNativePath(path: String, convention: PathConvention?)
    case unsupportedConfigPath(path: String, convention: PathConvention)
    case missingBaseConvention(cwd: String)
    case missingHomeDirectory(path: String)
    case mismatchedConvention(
        path: String,
        pathConvention: PathConvention,
        cwd: String,
        convention: PathConvention
    )
    /// `#[error(transparent)] PathUri(#[from] PathUriParseError)`.
    case pathUri(PathUriParseError)

    public var description: String {
        switch self {
        case .opaqueFallback(let path):
            return "opaque fallback path URI `\(path)` cannot be recovered as a native path"
        case .incompatibleConvention(let path, let convention):
            return "path URI `\(path)` cannot be rendered using \(convention) path syntax"
        case .invalidNativePath(let path, let convention):
            let suffix = convention.map { " using \($0) path syntax" } ?? ""
            return "path `\(path)` is not absolute\(suffix)"
        case .unsupportedConfigPath(let path, let convention):
            return "unsupported configuration path \(rustDebugString(path)) using \(convention) path syntax"
        case .missingBaseConvention(let cwd):
            return "path URI `\(cwd)` has no path convention"
        case .missingHomeDirectory(let path):
            return "cannot resolve home-relative path `\(path)` without an executor home"
        case .mismatchedConvention(let path, let pathConvention, let cwd, let convention):
            return "path \(path) uses \(pathConvention) paths, but executor cwd \(cwd) uses \(convention) paths"
        case .pathUri(let error):
            return error.description
        }
    }
}

/// Rust's `{:?}` string formatting (used by `UnsupportedConfigPath`).
func rustDebugString(_ string: String) -> String {
    var out = "\""
    for character in string {
        switch character {
        case "\\": out += "\\\\"
        case "\"": out += "\\\""
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\0": out += "\\0"
        default: out.append(character)
        }
    }
    out += "\""
    return out
}
