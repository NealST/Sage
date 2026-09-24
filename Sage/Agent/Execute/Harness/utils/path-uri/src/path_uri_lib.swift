//
//  lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-uri/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Typed, immutable `file:` URIs with cross-platform path inspection.
//
//  Adaptations:
//  - `url::Url` is provided by the local `FileUrl` type (file_url.swift);
//    `urlencoding`/`base64` by url_encoding.swift. Non-ASCII host names are
//    rejected instead of punycode-encoded (both routes converge on the
//    opaque fallback at the `PathUri` level).
//  - `AbsolutePathBuf` is a UTF-8 `String` wrapper, so non-UTF-8 native
//    paths cannot be represented: `fromAbsPath` encodes UTF-8 bytes and
//    `toAbsPath` rejects non-UTF-8 opaque payloads (upstream round-trips
//    raw bytes on Unix). Documented gap; the affected upstream tests are
//    skipped in the ported suite.
//  - `std::io::Result` maps to `throws` with `IOError` (io_error.swift).
//  - Windows-only `cfg(windows)` branches (UTF-16LE opaque payloads in
//    `toAbsPath`, `PathConvention.native() == .windows`) are compiled out;
//    Sage runs on macOS only (plan §2.3). The Windows *parsing* logic is
//    host-independent and fully ported.
//  - `schemars`/`ts_rs` derives carry no runtime semantics and are not
//    ported.
//

import Foundation

/// `FILE_SCHEME`.
public let fileScheme = "file"

/// `BAD_PATH_URI_PREFIX`.
let badPathUriPrefix = "file:///%00/bad/path/"

// MARK: - byte/character helpers (Rust `u8`/`str` ASCII utilities)

func isAsciiAlpha(_ byte: UInt8) -> Bool {
    (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
        || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
}

func asciiLower(_ byte: UInt8) -> UInt8 {
    byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
}

/// `str::eq_ignore_ascii_case` (byte-wise ASCII case folding).
func asciiCaseInsensitiveEqual(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8)
    let b = Array(rhs.utf8)
    guard a.count == b.count else { return false }
    return zip(a, b).allSatisfy { asciiLower($0) == asciiLower($1) }
}

/// `str::split` semantics: empty input yields `[""]`, empty fields kept.
func rustSplit(_ string: String, separator: Character) -> [String] {
    rustSplit(string, where: { $0 == separator })
}

/// `str::split` with a char predicate.
func rustSplit(_ string: String, where isSeparator: (Character) -> Bool) -> [String] {
    var result: [String] = []
    var current = ""
    for character in string {
        if isSeparator(character) {
            result.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    result.append(current)
    return result
}

// MARK: - PathUri

/// An immutable, cross-platform representation of a `file:` URI.
///
/// Only the `file:` scheme is currently accepted. Construction validates the
/// URL, and the URI cannot be mutated after construction. `basename`,
/// `parent`, and `join` operate on URI path segments without interpreting
/// them using the operating system running Codex. Fallback URIs created by
/// `fromAbsPath` are opaque to these lexical operations.
public struct PathUri {
    /// The wrapped URL (`pub(crate)` upstream; visible to `@testable`).
    let url: FileUrl

    /// `TryFrom<Url> for PathUri`.
    init(validating url: FileUrl) throws {
        guard url.scheme == fileScheme else {
            throw PathUriParseError.unsupportedScheme(url.scheme)
        }
        try validateFileUrl(url)
        var url = withoutLocalhostAuthority(url)
        url = withNormalizedWindowsDriveLetter(url)
        self.url = url
    }

    /// Parses and validates a `file:` URI (`parse` / `FromStr`).
    public static func parse(_ uri: String) throws -> PathUri {
        let url: FileUrl
        do {
            url = try FileUrl.parse(uri)
        } catch let error as FileUrlParseError {
            throw PathUriParseError.invalidUri(error)
        }
        return try PathUri(validating: url)
    }

    /// Converts an absolute path on the current host to a `file:` URI.
    ///
    /// Paths without a valid URI representation are replaced by
    /// `file:///%00/bad/path/<base64>`, where `<base64>` is the URL-safe,
    /// unpadded encoding of the original path bytes. The encoded null
    /// reserves a URI namespace that cannot collide with a real path.
    public static func fromAbsPath(_ path: AbsolutePathBuf) -> PathUri {
        if let url = FileUrl.fromFilePath(path.path),
           let uri = try? PathUri(validating: url),
           uri.url.hostStr != "",
           uri.inferPathConvention() == PathConvention.native() {
            return uri
        }
        // Unix upstream uses the raw OS bytes; our paths are UTF-8 strings.
        return fromOpaquePathBytes(Array(path.path.utf8))
    }

    /// `From<AbsolutePathBuf>`.
    public init(_ path: AbsolutePathBuf) {
        self = PathUri.fromAbsPath(path)
    }

    /// Parses an absolute native path using the specified path convention,
    /// falling back to an opaque URI when its ordinary URI spelling would
    /// imply a different convention (`pub(crate)`).
    static func fromAbsoluteNativePath(_ path: String, convention: PathConvention) -> PathUri? {
        guard let uri = (convention == .posix ? parsePosixPath(path) : parseWindowsPath(path))
        else {
            return nil
        }
        if uri.url.hostStr != "" && uri.inferPathConvention() == convention {
            return uri
        }
        switch convention {
        case .posix:
            return fromOpaquePathBytes(Array(path.utf8))
        case .windows:
            return windowsOpaquePathUri(path)
        }
    }

    static func fromOpaquePathBytes(_ pathBytes: [UInt8]) -> PathUri {
        let encodedPath = Base64URLNoPad.encode(pathBytes)
        do {
            return try PathUri.parse(badPathUriPrefix + encodedPath)
        } catch {
            preconditionFailure("URL-safe base64 always produces a valid fallback path URI")
        }
    }

    /// Converts a path on the current host to a `file:` URI
    /// (`from_host_native_path`). Relative paths are reported as invalid
    /// input.
    public static func fromHostNativePath(_ path: String) throws -> PathUri {
        let absolute = try AbsolutePathBuf.fromAbsolutePathChecked(path)
        return fromAbsPath(absolute)
    }

    /// Returns the percent-encoded URI path (`encoded_path`). The URL
    /// authority is not included.
    public func encodedPath() -> String {
        url.path
    }

    /// Returns the percent-decoded URI path bytes (`decoded_path_bytes`).
    public func decodedPathBytes() -> [UInt8] {
        urlDecodeBinary(Array(encodedPath().utf8))
    }

    func windowsIdentityPathBytes() -> [UInt8]? {
        guard inferPathConvention() == .windows, opaqueFallbackBytes() == nil else {
            return nil
        }
        for segment in url.pathSegments {
            let decoded = urlDecodeBinary(Array(segment.utf8))
            if decoded.contains(UInt8(ascii: "/")) || decoded.contains(UInt8(ascii: "\\")) {
                return nil
            }
        }
        // Decode equivalent URI spellings here; comparisons and hashing apply
        // ASCII case folding to these shared Windows identity bytes.
        return urlDecodeBinary(Array(url.path.utf8))
    }

    func opaqueFallbackBytes() -> [UInt8]? {
        decodeBadPathUri(url)
    }

    /// Infers the native path convention represented by this URI
    /// (`infer_path_convention`). A URI authority is treated as a Windows UNC
    /// host, and a leading drive-letter segment such as `C:` is treated as a
    /// Windows drive. All other ordinary file URIs are treated as POSIX
    /// paths. Opaque fallback URIs are inspected for an absolute POSIX byte
    /// prefix or an absolute Windows UTF-16LE prefix.
    public func inferPathConvention() -> PathConvention? {
        if let pathBytes = opaqueFallbackBytes() {
            return inferOpaquePathConvention(pathBytes)
        }
        if url.hostStr != nil {
            return .windows
        }
        let hasWindowsDrive = url.pathSegments
            .first(where: { !$0.isEmpty })
            .map(isWindowsDriveUriSegment) ?? false
        return hasWindowsDrive ? .windows : .posix
    }

    /// Renders this URI using the native path syntax inferred from its shape
    /// (`inferred_native_path_string`). Falls back to the canonical URI
    /// string when the convention cannot be inferred or represented.
    public func inferredNativePathString() -> String {
        if let convention = inferPathConvention(),
           let rendered = try? LegacyAppPathString.fromPathUri(self, convention: convention) {
            return rendered.intoString()
        }
        return description
    }

    /// Returns the decoded final URI path segment, or nil for the URI root
    /// or an opaque fallback URI (`basename`). Non-UTF-8 segments keep their
    /// percent-encoded spelling.
    public func basename() -> String? {
        if decodeBadPathUri(url) != nil {
            return nil
        }
        return url.pathSegments.last(where: { !$0.isEmpty }).map(decodeUriPath)
    }

    /// Renders this URI as a path-flavored string using its inferred
    /// convention (`to_path_buf`; `PathBuf` is a String in this port).
    public func toPathBuf() -> String {
        inferredNativePathString()
    }

    /// Returns the lexical parent without crossing the inferred native path
    /// root (`parent`).
    public func parent() -> PathUri? {
        if decodeBadPathUri(url) != nil {
            return nil
        }
        guard let convention = inferPathConvention() else {
            return nil
        }
        // In URI form, both a Windows drive root (`file:///C:`) and a UNC
        // share root (`file://server/share`) retain one non-empty path
        // segment. Keep that segment as the anchor so parent traversal cannot
        // produce a URI that is not an absolute Windows path.
        let anchorDepth = convention == .windows ? 1 : 0
        let depth = url.pathSegments.filter { !$0.isEmpty }.count
        if depth <= anchorDepth {
            return nil
        }
        var url = self.url
        url.popIfEmptySegment()
        url.popSegment()
        return PathUri(unchecked: url)
    }

    /// Returns this URI and each lexical parent up to its inferred native
    /// path root (`ancestors`).
    public func ancestors() -> [PathUri] {
        var result: [PathUri] = [self]
        var current = self
        while let parent = current.parent() {
            result.append(parent)
            current = parent
        }
        return result
    }

    /// Returns true when this URI is lexically equal to or below `base`
    /// (`starts_with`). Windows path segments are compared
    /// ASCII-case-insensitively; POSIX path segments remain case-sensitive.
    public func startsWith(_ base: PathUri) -> Bool {
        if self == base {
            return true
        }
        if decodeBadPathUri(url) != nil || decodeBadPathUri(base.url) != nil {
            return false
        }
        if url.hostStr != base.url.hostStr {
            return false
        }
        let convention = inferPathConvention()
        if convention != base.inferPathConvention() {
            return false
        }
        let resolved = convention ?? .posix
        guard let pathSegments = containmentPathSegments(url, resolved),
              let baseSegments = containmentPathSegments(base.url, resolved) else {
            return false
        }
        return nativePathSegmentsStartWith(pathSegments, baseSegments, resolved)
    }

    /// Returns whether the lexical subtrees rooted at these URIs overlap
    /// (`overlaps`). nil when either URI does not expose unambiguous lexical
    /// components.
    public func overlaps(_ other: PathUri) -> Bool? {
        if self == other {
            return true
        }
        guard lexicalDepth() != nil, other.lexicalDepth() != nil else {
            return nil
        }
        return startsWith(other) || other.startsWith(self)
    }

    /// Returns true for a fallback URI that losslessly stores native path
    /// bytes (`is_opaque`).
    public func isOpaque() -> Bool {
        opaqueFallbackBytes() != nil
    }

    /// Returns the number of non-empty path segments when this URI is safe
    /// for lexical containment (`lexical_depth`).
    public func lexicalDepth() -> Int? {
        if decodeBadPathUri(url) != nil {
            return nil
        }
        guard let convention = inferPathConvention() else {
            return nil
        }
        return containmentPathSegments(url, convention)?.count
    }

    /// Returns the decoded relative path from `base` to this URI
    /// (`relative_path_from`), using the separators of the inferred
    /// convention.
    public func relativePathFrom(_ base: PathUri) -> String? {
        if self == base {
            return ""
        }
        if decodeBadPathUri(url) != nil
            || decodeBadPathUri(base.url) != nil
            || url.hostStr != base.url.hostStr
            || inferPathConvention() != base.inferPathConvention() {
            return nil
        }
        guard let convention = inferPathConvention(),
              let pathSegments = containmentPathSegments(url, convention),
              let baseSegments = containmentPathSegments(base.url, convention),
              nativePathSegmentsStartWith(pathSegments, baseSegments, convention) else {
            return nil
        }
        let separator = convention == .posix ? "/" : "\\"
        return pathSegments.dropFirst(baseSegments.count)
            .map(decodeUriPath)
            .joined(separator: separator)
    }

    /// Lexically resolves native absolute or relative path text against this
    /// URI (`join`). See upstream docs for the full contract.
    public func join(_ path: String) throws -> PathUri {
        if path.contains("\0") {
            throw PathUriParseError.invalidFileUriPath(path: path)
        }
        if path.isEmpty {
            return self
        }
        guard let convention = inferPathConvention() else {
            throw PathUriParseError.invalidFileUriPath(path: description)
        }
        // An absolute native path is already fully resolved, so replace the
        // base URI's main path instead of appending it.
        if let absolute = PathUri.fromAbsoluteNativePath(path, convention: convention) {
            return absolute
        }
        var path = path
        if convention == .windows {
            let pathBytes = Array(path.utf8)
            if pathBytes.count >= 2, isAsciiAlpha(pathBytes[0]),
               pathBytes[1] == UInt8(ascii: ":") {
                let sameDrive = url.pathSegments
                    .first(where: { !$0.isEmpty })
                    .map { segment in
                        isWindowsDriveUriSegment(segment)
                            && asciiLower(Array(segment.utf8)[0]) == asciiLower(pathBytes[0])
                    } ?? false
                if !sameDrive {
                    throw PathUriParseError.invalidFileUriPath(path: path)
                }
                path = String(path.dropFirst(2))
            }
        }
        let pathBytes = Array(path.utf8)
        if decodeBadPathUri(url) != nil {
            throw PathUriParseError.invalidFileUriPath(path: description)
        }

        var url = self.url
        let anchorDepth = convention == .windows ? 1 : 0
        var depth = url.pathSegments.filter { !$0.isEmpty }.count
        let windowsRootRelative = convention == .windows
            && !pathBytes.isEmpty
            && isWindowsSeparatorByte(pathBytes[0])
            && !(pathBytes.count > 1 && isWindowsSeparatorByte(pathBytes[1]))
        url.popIfEmptySegment()
        if windowsRootRelative {
            while depth > anchorDepth {
                url.popSegment()
                depth -= 1
            }
        }
        let splitPath = convention == .windows
            ? path.replacingOccurrences(of: "\\", with: "/")
            : path
        for component in rustSplit(splitPath, separator: "/") {
            switch component {
            case "", ".":
                break
            case "..":
                if depth > anchorDepth {
                    url.popSegment()
                    depth -= 1
                }
            default:
                url.pushSegment(component)
                depth += 1
            }
        }
        return try PathUri(validating: url)
    }

    /// Lexically resolves a relative native path that remains at or below
    /// this URI (`join_descendant`).
    public func joinDescendant(_ path: String) throws -> PathUri {
        let descendant = try join(path)
        let windows = inferPathConvention() == .windows
        if path.hasPrefix("/")
            || (windows
                && (path.hasPrefix("\\")
                    || PathConvention.windows.pathSegments(path).contains { $0.contains(":") }))
            || !descendant.startsWith(self) {
            throw PathUriParseError.joinPathMustBeDescendant(path)
        }
        return descendant
    }

    /// Converts this file URI to a path using the current host's path rules
    /// (`to_abs_path`). The URI's inferred path convention must match the
    /// current host.
    public func toAbsPath() throws -> AbsolutePathBuf {
        func invalidInput() -> IOError {
            IOError.invalidInput(PathUriParseError.invalidFileUriPath(path: description).description)
        }
        // The upstream Windows-only containment pre-check is `cfg`-gated;
        // `PathConvention.native()` is `.posix` here.
        guard inferPathConvention() == PathConvention.native() else {
            throw invalidInput()
        }
        if let pathBytes = decodeBadPathUri(url) {
            // Unix upstream builds the path from raw bytes; UTF-8 only here.
            if let decodedPath = String(bytes: pathBytes, encoding: .utf8),
               let path = try? AbsolutePathBuf.fromAbsolutePathChecked(decodedPath),
               PathUri.fromAbsPath(path) == self {
                return path
            }
            throw invalidInput()
        }
        guard let filePath = url.toFilePath(),
              let path = try? AbsolutePathBuf.fromAbsolutePathChecked(filePath) else {
            throw invalidInput()
        }
        return path
    }

    /// Returns a clone of the canonical URL (`to_url`).
    public func toUrl() -> FileUrl {
        url
    }

    /// Bypasses validation; used where upstream constructs `Self(url)`
    /// directly from an already-validated URL (`parent`).
    init(unchecked url: FileUrl) {
        self.url = url
    }
}

extension PathUri: Equatable {
    public static func == (lhs: PathUri, rhs: PathUri) -> Bool {
        if lhs.url == rhs.url {
            return true
        }
        guard let path = lhs.windowsIdentityPathBytes(),
              let otherPath = rhs.windowsIdentityPathBytes() else {
            return false
        }
        let lhsHost = lhs.url.hostStr
        let rhsHost = rhs.url.hostStr
        guard lhsHost == rhsHost else {
            return false
        }
        guard path.count == otherPath.count else {
            return false
        }
        return zip(path, otherPath).allSatisfy { asciiLower($0) == asciiLower($1) }
    }
}

extension PathUri: Hashable {
    public func hash(into hasher: inout Hasher) {
        // Preserve URL hashing for POSIX paths; Windows paths must hash the
        // same decoded, ASCII-folded identity that `==` compares.
        guard let path = windowsIdentityPathBytes() else {
            hasher.combine(url.asString)
            return
        }
        hasher.combine(url.hostStr)
        hasher.combine(path.count)
        for byte in path {
            hasher.combine(asciiLower(byte))
        }
    }
}

extension PathUri: CustomStringConvertible {
    public var description: String {
        url.asString
    }
}

extension PathUri: Codable {
    /// Serde represents a `PathUri` as its canonical URI string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            self = try PathUri.parse(value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url.asString)
    }
}

// MARK: - free functions

/// Removes the local `localhost` alias while retaining non-local UNC
/// authority (`without_localhost_authority`).
func withoutLocalhostAuthority(_ url: FileUrl) -> FileUrl {
    var url = url
    if url.hostStr == "localhost" {
        try? url.setHost(nil)
    }
    return url
}

/// `with_normalized_windows_drive_letter`.
func withNormalizedWindowsDriveLetter(_ url: FileUrl) -> FileUrl {
    guard url.hostStr == nil else {
        return url
    }
    let path = url.path
    let pathBytes = Array(path.utf8)
    guard let driveStart = pathBytes.firstIndex(where: { $0 != UInt8(ascii: "/") }) else {
        return url
    }
    // `driveStart` counts leading ASCII `/` bytes, so offset indexing is safe.
    let afterSlashes = String(path.dropFirst(driveStart))
    let drive = afterSlashes.split(separator: "/", omittingEmptySubsequences: false)
        .first.map(String.init) ?? ""
    guard isWindowsDriveUriSegment(drive),
          let first = drive.utf8.first,
          !(first >= UInt8(ascii: "A") && first <= UInt8(ascii: "Z")) else {
        return url
    }
    let driveLetter = Character(UnicodeScalar(first - 32))
    let normalizedPath = String(path.prefix(driveStart)) + String(driveLetter)
        + String(afterSlashes.dropFirst())
    var url = url
    url.setPath(normalizedPath)
    return url
}

/// Percent-decodes a URI path when it is valid UTF-8 (`decode_uri_path`);
/// otherwise the encoded spelling is retained.
func decodeUriPath(_ path: String) -> String {
    urlDecode(path) ?? path
}

/// Returns the original platform path bytes from a canonical bad-path URI
/// (`decode_bad_path_uri`).
func decodeBadPathUri(_ url: FileUrl) -> [UInt8]? {
    let text = url.asString
    guard text.hasPrefix(badPathUriPrefix) else {
        return nil
    }
    let encodedPath = String(text.dropFirst(badPathUriPrefix.count))
    if encodedPath.isEmpty || encodedPath.contains("/") {
        return nil
    }
    guard let pathBytes = Base64URLNoPad.decode(encodedPath),
          Base64URLNoPad.encode(pathBytes) == encodedPath else {
        return nil
    }
    return pathBytes
}

/// `is_windows_drive_uri_segment`: `C:` or `C%3A` (either hex case).
func isWindowsDriveUriSegment(_ segment: String) -> Bool {
    let bytes = Array(segment.utf8)
    guard let drive = bytes.first, isAsciiAlpha(drive) else {
        return false
    }
    if bytes.count == 2 {
        return bytes[1] == UInt8(ascii: ":")
    }
    if bytes.count == 4 {
        return bytes[1] == UInt8(ascii: "%") && bytes[2] == UInt8(ascii: "3")
            && (bytes[3] == UInt8(ascii: "A") || bytes[3] == UInt8(ascii: "a"))
    }
    return false
}

/// `containment_path_segments`: non-empty segments, rejecting encoded native
/// separators.
func containmentPathSegments(_ url: FileUrl, _ convention: PathConvention) -> [String]? {
    let segments = url.pathSegments.filter { !$0.isEmpty }
    let hasEncodedSeparator = segments.contains { segment in
        urlDecodeBinary(Array(segment.utf8)).contains {
            $0 == UInt8(ascii: "/") || (convention == .windows && $0 == UInt8(ascii: "\\"))
        }
    }
    return hasEncodedSeparator ? nil : segments
}

/// `native_path_segments_start_with`.
func nativePathSegmentsStartWith(
    _ pathSegments: [String],
    _ baseSegments: [String],
    _ convention: PathConvention
) -> Bool {
    guard pathSegments.count >= baseSegments.count else {
        return false
    }
    switch convention {
    case .posix:
        return zip(pathSegments, baseSegments).allSatisfy { path, base in
            urlDecodeBinary(Array(path.utf8)) == urlDecodeBinary(Array(base.utf8))
        }
    case .windows:
        return zip(pathSegments, baseSegments).allSatisfy { path, base in
            asciiCaseInsensitiveEqual(path, base)
                || asciiCaseInsensitiveEqual(decodeUriPath(path), decodeUriPath(base))
        }
    }
}

/// `infer_opaque_path_convention`.
func inferOpaquePathConvention(_ pathBytes: [UInt8]) -> PathConvention? {
    if pathBytes.first == UInt8(ascii: "/") {
        return .posix
    }
    guard pathBytes.count % 2 == 0 else {
        return nil
    }
    let pathWide = stride(from: 0, to: pathBytes.count, by: 2)
        .map { UInt16(pathBytes[$0]) | UInt16(pathBytes[$0 + 1]) << 8 }
    guard let first = pathWide.first, pathWide.count > 1 else {
        return nil
    }
    let second = pathWide[1]
    let hasDrive = first <= 0xFF && isAsciiAlpha(UInt8(first))
        && second == UInt16(UnicodeScalar(":").value)
    let hasUncPrefix = first == UInt16(UnicodeScalar("\\").value)
        && second == UInt16(UnicodeScalar("\\").value)
    return (hasDrive || hasUncPrefix) ? .windows : nil
}

/// `parse_posix_path`.
func parsePosixPath(_ path: String) -> PathUri? {
    guard path.hasPrefix("/") else {
        return nil
    }
    let rest = String(path.dropFirst())
    if rest.contains("\0") {
        return PathUri.fromOpaquePathBytes(Array(path.utf8))
    }
    return pathUriFromSegments(
        convention: .posix,
        host: nil,
        segments: rustSplit(rest, separator: "/")
    )
}

/// `parse_windows_path`.
func parseWindowsPath(_ path: String) -> PathUri? {
    if let normalizedPath = normalizeWindowsDevicePath(path) {
        if normalizedPath.hasPrefix(#"\\"#) {
            let uncPath = String(normalizedPath.dropFirst(2))
            let components = rustSplit(uncPath, where: isWindowsSeparatorChar)
            let first = components.count > 0 ? components[0] : nil
            let second = components.count > 1 ? components[1] : nil
            let bad = ["", ".", ".."]
            if first.map({ bad.contains($0) }) ?? true
                || second.map({ bad.contains($0) }) ?? true {
                return windowsOpaquePathUri(path)
            }
        }
        if let uri = parseUnnormalizedWindowsPath(normalizedPath),
           uri.inferPathConvention() == .windows,
           uri.opaqueFallbackBytes() == nil,
           !normalizedPath.hasPrefix(#"\\"#)
            || (uri.url.hostStr.map { !$0.isEmpty } ?? false) {
            return uri
        }
        return windowsOpaquePathUri(path)
    }
    return parseUnnormalizedWindowsPath(path)
}

/// `parse_unnormalized_windows_path`.
func parseUnnormalizedWindowsPath(_ path: String) -> PathUri? {
    let bytes = Array(path.utf8)
    let usesNamespace = bytes.count >= 4
        && isWindowsSeparatorByte(bytes[0])
        && isWindowsSeparatorByte(bytes[1])
        && (bytes[2] == UInt8(ascii: ".") || bytes[2] == UInt8(ascii: "?"))
        && isWindowsSeparatorByte(bytes[3])
    if usesNamespace || path.contains("\0") {
        return windowsOpaquePathUri(path)
    }

    if bytes.count >= 3,
       isAsciiAlpha(bytes[0]),
       bytes[1] == UInt8(ascii: ":"),
       isWindowsSeparatorByte(bytes[2]) {
        // The prefix is ASCII, so character-based slicing is safe.
        let drive = String(path.prefix(2))
        let rest = String(path.dropFirst(3))
        return pathUriFromSegments(
            convention: .windows,
            host: nil,
            segments: [drive] + rustSplit(rest, where: isWindowsSeparatorChar)
        )
    }

    if bytes.count >= 2,
       isWindowsSeparatorByte(bytes[0]),
       isWindowsSeparatorByte(bytes[1]) {
        let rest = String(path.dropFirst(2))
        var components = rustSplit(rest, where: isWindowsSeparatorChar)[...]
        guard let host = components.popFirst(), !host.isEmpty else {
            return nil
        }
        guard let share = components.popFirst(), !share.isEmpty else {
            return nil
        }
        if host == "." || host == ".." || share == "." || share == ".." {
            return windowsOpaquePathUri(path)
        }
        if let uri = pathUriFromSegments(
            convention: .windows,
            host: host,
            segments: [share] + components
        ), let parsed = uri.url.hostStr, asciiCaseInsensitiveEqual(parsed, host) {
            return uri
        }
        return windowsOpaquePathUri(path)
    }

    return nil
}

/// `windows_opaque_path_uri`: UTF-16LE bytes in the opaque fallback.
func windowsOpaquePathUri(_ path: String) -> PathUri {
    var pathBytes: [UInt8] = []
    for unit in path.utf16 {
        pathBytes.append(UInt8(unit & 0xFF))
        pathBytes.append(UInt8(unit >> 8))
    }
    return PathUri.fromOpaquePathBytes(pathBytes)
}

/// `is_windows_separator_char`.
func isWindowsSeparatorChar(_ character: Character) -> Bool {
    character == "\\" || character == "/"
}

/// `is_windows_separator_byte` (`pub(crate)` upstream).
func isWindowsSeparatorByte(_ character: UInt8) -> Bool {
    character == UInt8(ascii: "\\") || character == UInt8(ascii: "/")
}

/// Rejects URI metadata that has no defined meaning for `file:` URIs
/// (`validate_common_known_uri`).
func validateCommonKnownUri(_ url: FileUrl) throws {
    if !url.username.isEmpty || url.password != nil {
        throw PathUriParseError.credentialsNotAllowed
    }
    if url.port != nil {
        throw PathUriParseError.portNotAllowed
    }
    if url.query != nil {
        throw PathUriParseError.queryNotAllowed
    }
    if url.fragment != nil {
        throw PathUriParseError.fragmentNotAllowed
    }
}

/// Applies the common URI checks plus `file:` path-byte restrictions
/// (`validate_file_url`).
func validateFileUrl(_ url: FileUrl) throws {
    try validateCommonKnownUri(url)
    // `Url` accepts `%00`, but native path APIs use null as a terminator and
    // `Url::to_file_path` cannot represent a decoded null byte.
    if urlDecodeBinary(Array(url.path.utf8)).contains(0), decodeBadPathUri(url) == nil {
        throw PathUriParseError.invalidFileUriPath(path: url.asString)
    }
}

// MARK: - PathUriParseError

/// `PathUriParseError`.
public enum PathUriParseError: Error, Equatable, CustomStringConvertible {
    /// `InvalidUri(#[from] url::ParseError)`.
    case invalidUri(FileUrlParseError)
    case unsupportedScheme(String)
    case invalidFileUriPath(path: String)
    case credentialsNotAllowed
    case portNotAllowed
    case queryNotAllowed
    case fragmentNotAllowed
    case joinPathMustBeDescendant(String)

    public var description: String {
        switch self {
        case .invalidUri(let error):
            return "invalid URI: \(error)"
        case .unsupportedScheme(let scheme):
            return "unsupported path URI scheme `\(scheme)`"
        case .invalidFileUriPath(let path):
            // `std::env::consts::OS` is "macos" here.
            return "'\(path)' is invalid on 'macos'"
        case .credentialsNotAllowed:
            return "credentials are not allowed in path URIs"
        case .portNotAllowed:
            return "ports are not allowed in path URIs"
        case .queryNotAllowed:
            return "query parameters are not allowed in path URIs"
        case .fragmentNotAllowed:
            return "fragments are not allowed in path URIs"
        case .joinPathMustBeDescendant(let path):
            return "path `\(path)` must resolve to a relative descendant when joining a path URI"
        }
    }
}

// MARK: - PathConvention

/// Path syntax used to render a `PathUri` as an operating-system path
/// (`PathConvention`). Serde uses snake_case.
public enum PathConvention: String, Codable, Sendable {
    case posix
    case windows

    /// Returns the path convention used by the current process
    /// (`native()`; `cfg(unix)` upstream).
    public static func native() -> PathConvention {
        #if os(Windows)
        return .windows
        #else
        return .posix
        #endif
    }

    /// Returns the suffix of `~` paths using this grammar's separators
    /// (`home_relative_suffix`). Named-user paths such as `~someone/private`
    /// are not home-relative.
    public func homeRelativeSuffix(_ path: String) -> String? {
        guard path.hasPrefix("~") else {
            return nil
        }
        let suffix = String(path.dropFirst())
        guard suffix.isEmpty
                || suffix.hasPrefix("/")
                || (self == .windows && suffix.hasPrefix("\\")) else {
            return nil
        }
        return suffix
    }

    /// Splits absolute or relative native path text into lexical segments
    /// (`path_segments`). Empty segments are retained.
    public func pathSegments(_ path: String) -> [String] {
        switch self {
        case .posix:
            return rustSplit(path, separator: "/")
        case .windows:
            return rustSplit(path, where: { $0 == "/" || $0 == "\\" })
        }
    }
}

extension PathConvention: CustomStringConvertible {
    public var description: String {
        switch self {
        case .posix: return "POSIX"
        case .windows: return "Windows"
        }
    }
}
