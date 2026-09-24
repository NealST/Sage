//
//  file_url.swift
//  CodexUtils
//
//  Sage addition (no codex counterpart).
//
//  Stands in for the `url` crate (`url::Url`, pinned 2.5.x), restricted to
//  the surface `codex-utils-path-uri` uses: WHATWG `file:` URL parsing and
//  serialization, path-segment mutation, host handling, and Unix
//  `to_file_path`. All behaviors were pinned empirically against
//  url 2.5.8 on macOS (probe transcripts in the Phase 1 batch notes):
//
//  - parse: tab/LF/CR stripped; scheme lowercased; `\` → `/`; dot segments
//    (incl. `%2e` forms) resolved; path bytes percent-encoded with the
//    WHATWG path set (C0, space, " # < > ? ` { }, DEL, non-ASCII) while
//    valid/invalid `%` sequences pass through untouched; empty or
//    `localhost` authority → no host; authority drive letters (`C:`/`C|`)
//    move to the path; hosts lowercased, IPv4 numbers normalized, non-ASCII
//    rejected (url crate applies punycode — a documented gap; at the
//    `PathUri` level both routes end in the opaque fallback).
//  - `set_host(None)` leaves an *empty* host (`host_str() == Some("")`),
//    unlike parse, which maps the empty authority to `None`. This asymmetry
//    is load-bearing for `PathUri::from_abs_path`.
//  - path segment mutation percent-encodes with the segment set (path set
//    + `%` + `/`).
//

import Foundation

/// `url::ParseError` (subset; Display strings match upstream).
public enum FileUrlParseError: Error, Equatable, CustomStringConvertible, Sendable {
    case relativeUrlWithoutBase
    case idnaError
    case invalidIpv4Address

    public var description: String {
        switch self {
        case .relativeUrlWithoutBase: return "relative URL without a base"
        case .idnaError: return "invalid international domain name"
        case .invalidIpv4Address: return "invalid IPv4 address"
        }
    }
}

/// Minimal immutable-by-convention URL. Equality and hashing follow the
/// canonical serialization, like `url::Url`.
public struct FileUrl: Equatable, Hashable {
    /// `host_str()` mapping: `.none` → nil, `.empty` → `Some("")`
    /// (only reachable via `setHost(nil)`), `.name(let h)` → `Some(h)`.
    public enum Host: Equatable, Hashable {
        case none
        case empty
        case name(String)
    }

    /// Lowercased scheme. For non-`file` schemes only `scheme`/`rest` are
    /// meaningful (PathUri only reads the scheme to reject it).
    let scheme: String
    /// Original post-scheme text for non-`file` schemes.
    let rest: String
    var host: Host
    /// Path segments after the root; `[""]` is `/`. Always canonical
    /// (percent-encoded, dot segments resolved) for `file:` URLs.
    var segments: [String]
    var query: String?
    var fragment: String?

    // MARK: - parse

    /// `Url::parse`. Non-`file` schemes parse without further validation
    /// (sufficient for `PathUri`'s scheme check).
    static func parse(_ input: String) throws -> FileUrl {
        // WHATWG pre-processing: strip ASCII tab/LF/CR anywhere, then trim
        // leading/trailing C0 controls and spaces.
        var text = input
        text.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }
        text = String(text.drop(while: { $0.asciiValue.map { $0 <= 0x20 } ?? false }))
        text = String(text.reversed().drop(while: { $0.asciiValue.map { $0 <= 0x20 } ?? false }).reversed())

        guard let schemeRange = text.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#,
                                           options: .regularExpression) else {
            throw FileUrlParseError.relativeUrlWithoutBase
        }
        let scheme = text[schemeRange].dropLast().lowercased()
        let rest = String(text[schemeRange.upperBound...])
        guard scheme == "file" else {
            return FileUrl(scheme: scheme, rest: rest, host: .none,
                           segments: [""], query: nil, fragment: nil)
        }

        // `file:` treats `\` as a path separator.
        var remainder = rest.replacingOccurrences(of: "\\", with: "/")

        var fragment: String?
        if let hash = remainder.firstIndex(of: "#") {
            fragment = String(remainder[remainder.index(after: hash)...])
            remainder = String(remainder[..<hash])
        }
        var query: String?
        if let mark = remainder.firstIndex(of: "?") {
            query = String(remainder[remainder.index(after: mark)...])
            remainder = String(remainder[..<mark])
        }

        var host: Host = .none
        var pathPart = remainder
        var drivePrefix: String?
        if remainder.hasPrefix("//") {
            let afterSlashes = remainder.dropFirst(2)
            let end = afterSlashes.firstIndex(of: "/") ?? afterSlashes.endIndex
            let authority = String(afterSlashes[..<end])
            pathPart = String(afterSlashes[end...])
            switch try parseFileAuthority(authority) {
            case .none:
                host = .none
            case .name(let name):
                host = .name(name)
            case .drive(let letter):
                // `file://C|/x` / `file://C:/x`: the authority is a drive.
                drivePrefix = letter
            }
        }

        if let drivePrefix {
            pathPart = "/" + drivePrefix + pathPart
        }
        let segments = parsePathSegments(pathPart)
        return FileUrl(scheme: scheme, rest: rest, host: host,
                       segments: segments, query: query, fragment: fragment)
    }

    private enum AuthorityParse {
        case none
        case name(String)
        case drive(String)
    }

    private static func parseFileAuthority(_ authority: String) throws -> AuthorityParse {
        if authority.isEmpty {
            return .none
        }
        // Drive-letter authority (`C:` or `C|`) is path text, not a host.
        let bytes = Array(authority.utf8)
        if bytes.count == 2,
           bytes[0] >= UInt8(ascii: "A") && bytes[0] <= UInt8(ascii: "Z")
            || bytes[0] >= UInt8(ascii: "a") && bytes[0] <= UInt8(ascii: "z"),
           bytes[1] == UInt8(ascii: ":") || bytes[1] == UInt8(ascii: "|") {
            return .drive(String(UnicodeScalar(bytes[0])) + ":")
        }
        // `file:` URLs carry neither credentials nor ports; the url crate
        // surfaces both as an IDNA failure.
        if authority.contains("@") || authority.contains(":") {
            throw FileUrlParseError.idnaError
        }
        guard let decoded = urlDecode(authority) else {
            throw FileUrlParseError.idnaError
        }
        let lowercased = decoded.lowercased()
        if lowercased == "localhost" {
            return .none
        }
        if let ipv4 = try parseIPv4Host(lowercased) {
            return .name(ipv4)
        }
        // ASCII domain subset (see header: non-ASCII is rejected rather than
        // punycode-encoded).
        for scalar in lowercased.unicodeScalars {
            let ok = scalar.value < 0x80
                && (scalar >= "a" && scalar <= "z" || scalar >= "0" && scalar <= "9"
                    || scalar == "." || scalar == "-" || scalar == "_")
            if !ok {
                throw FileUrlParseError.idnaError
            }
        }
        return .name(lowercased)
    }

    /// WHATWG IPv4 parser. Returns nil when `host` is not IPv4-shaped
    /// (last part is not a number); throws for malformed IPv4.
    private static func parseIPv4Host(_ host: String) throws -> String? {
        var parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "" {
            parts.removeLast()
        }
        guard let last = parts.last, ipv4Number(last) != nil else {
            return nil
        }
        guard parts.count <= 4 else {
            throw FileUrlParseError.invalidIpv4Address
        }
        var numbers: [UInt64] = []
        for part in parts {
            guard let value = ipv4Number(part) else {
                throw FileUrlParseError.invalidIpv4Address
            }
            numbers.append(value)
        }
        for value in numbers.dropLast() where value > 255 {
            throw FileUrlParseError.invalidIpv4Address
        }
        let lastLimit: UInt64 = 1 << (8 * (5 - numbers.count))
        guard let lastValue = numbers.last, lastValue < lastLimit else {
            throw FileUrlParseError.invalidIpv4Address
        }
        var address = lastValue
        for (index, value) in numbers.dropLast().enumerated() {
            address += value << (8 * (3 - index))
        }
        return (0...3).map { String((address >> (8 * (3 - $0))) & 0xFF) }.joined(separator: ".")
    }

    private static func ipv4Number(_ part: String) -> UInt64? {
        guard !part.isEmpty else { return nil }
        if part.hasPrefix("0x") || part.hasPrefix("0X") {
            return UInt64(part.dropFirst(2), radix: 16)
        }
        if part.hasPrefix("0"), part.count > 1 {
            // Octal; invalid digits make it non-numeric.
            return UInt64(part.dropFirst(), radix: 8)
        }
        return UInt64(part, radix: 10)
    }

    // MARK: - path state

    /// WHATWG path state: split on `/`, resolve dot segments (including
    /// `%2e` spellings), percent-encode with the path encode set.
    static func parsePathSegments(_ pathPart: String) -> [String] {
        let path = pathPart.hasPrefix("/") ? pathPart : "/" + pathPart
        let raw = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        for (index, segment) in raw.enumerated() {
            let isLast = index == raw.count - 1
            if isSingleDotSegment(segment) {
                if isLast { out.append("") }
            } else if isDoubleDotSegment(segment) {
                if !out.isEmpty { out.removeLast() }
                if isLast { out.append("") }
            } else {
                out.append(segment)
            }
        }
        if out.isEmpty {
            out = [""]
        }
        if out[0] != "" {
            out.insert("", at: 0)
        }
        return out.dropFirst().map(encodePathSegment)
    }

    private static func isSingleDotSegment(_ segment: String) -> Bool {
        segment == "." || segment.lowercased() == "%2e"
    }

    private static func isDoubleDotSegment(_ segment: String) -> Bool {
        if segment == ".." { return true }
        let lowered = segment.lowercased()
        return lowered == "%2e." || lowered == ".%2e" || lowered == "%2e%2e"
    }

    /// Bytes encoded in the WHATWG path state (plus DEL and non-ASCII,
    /// matching the url crate). `%` sequences pass through untouched.
    private static func isPathEncodeByte(_ byte: UInt8) -> Bool {
        if byte < 0x20 || byte >= 0x7F { return true }
        switch byte {
        case UInt8(ascii: " "), UInt8(ascii: "\""), UInt8(ascii: "#"),
             UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "?"),
             UInt8(ascii: "`"), UInt8(ascii: "{"), UInt8(ascii: "}"):
            return true
        default:
            return false
        }
    }

    /// Parse-time segment encoding: keep `%` sequences verbatim.
    static func encodePathSegment(_ segment: String) -> String {
        let bytes = Array(segment.utf8)
        var out = ""
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "%") {
                out.append("%")
                index += 1
                continue
            }
            if isPathEncodeByte(byte) {
                out += String(format: "%%%02X", byte)
            } else {
                out.append(Character(UnicodeScalar(byte)))
            }
            index += 1
        }
        return out
    }

    /// Segment-mutation encoding (`PathSegmentsMut::push`/`extend`,
    /// `from_file_path`): the url crate's `SPECIAL_PATH_SEGMENT` set (file:
    /// is a special scheme) — the path set plus `%`, `/`, and `\`.
    static func encodeSegmentForPush(_ segment: String) -> String {
        var out = ""
        for byte in segment.utf8 {
            if byte == UInt8(ascii: "%") || byte == UInt8(ascii: "/")
                || byte == UInt8(ascii: "\\") || isPathEncodeByte(byte) {
                out += String(format: "%%%02X", byte)
            } else {
                out.append(Character(UnicodeScalar(byte)))
            }
        }
        return out
    }

    // MARK: - accessors

    /// `Url::path` — the percent-encoded path, always rooted.
    var path: String {
        "/" + segments.joined(separator: "/")
    }

    /// `Url::host_str`.
    var hostStr: String? {
        switch host {
        case .none: return nil
        case .empty: return ""
        case .name(let name): return name
        }
    }

    /// `Url::path_segments` (never nil for `file:` URLs).
    var pathSegments: [String] {
        segments
    }

    var username: String { "" }
    var password: String? { nil }
    var port: UInt16? { nil }

    /// `url::Url` equality compares canonical serializations, so the
    /// parse-produced absent host and the `setHost(nil)`-produced empty host
    /// (both serialize as `file:///…`) compare equal.
    public static func == (lhs: FileUrl, rhs: FileUrl) -> Bool {
        lhs.asString == rhs.asString
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(asString)
    }

    /// `Url::as_str` / `Display`.
    var asString: String {
        guard scheme == "file" else {
            return "\(scheme):\(rest)"
        }
        var out = "file://"
        if case .name(let name) = host {
            out += name
        }
        out += path
        if let query {
            out += "?" + query
        }
        if let fragment {
            out += "#" + fragment
        }
        return out
    }

    // MARK: - mutation (`Url::path_segments_mut`, `set_host`, `set_path`)

    /// `PathSegmentsMut::pop_if_empty`: removes one trailing empty segment,
    /// except if it is the only segment (`url.path() == "/"` stays put).
    mutating func popIfEmptySegment() {
        if segments.count > 1, segments.last == "" {
            segments.removeLast()
        }
    }

    /// `PathSegmentsMut::pop`: removing the only segment leaves the empty
    /// segment (`url.path() == "/"`).
    mutating func popSegment() {
        if !segments.isEmpty {
            segments.removeLast()
        }
        if segments.isEmpty {
            segments = [""]
        }
    }

    /// `PathSegmentsMut::push` (percent-encodes with the segment set).
    /// Like upstream `extend`, `"."` and `".."` segments are ignored, and no
    /// separator slash is added when the path is exactly `/` — pushing onto
    /// the root replaces the empty segment (while pushing after a trailing
    /// slash elsewhere yields a double slash).
    mutating func pushSegment(_ segment: String) {
        if segment == "." || segment == ".." {
            return
        }
        let encoded = FileUrl.encodeSegmentForPush(segment)
        if segments == [""] {
            segments = [encoded]
        } else {
            segments.append(encoded)
        }
    }

    /// `PathSegmentsMut::clear` + `extend`: `clear` leaves the minimal
    /// path `/`, and `extend` ignores `"."`/`".."` segments.
    mutating func replaceSegments<S: Sequence>(_ newSegments: S) where S.Element == String {
        segments = newSegments.filter { $0 != "." && $0 != ".." }
            .map(FileUrl.encodeSegmentForPush)
        if segments.isEmpty {
            segments = [""]
        }
    }

    /// `Url::set_host`. Note: `nil` yields the *empty* host (unlike parse).
    mutating func setHost(_ host: String?) throws {
        guard let host else {
            self.host = .empty
            return
        }
        switch try FileUrl.parseFileAuthority(host) {
        case .none:
            // Only reachable for "localhost"/""; the url crate keeps
            // "localhost" when set explicitly.
            self.host = host.lowercased() == "localhost" ? .name("localhost") : .none
        case .name(let name):
            self.host = .name(name)
        case .drive:
            throw FileUrlParseError.idnaError
        }
    }

    /// `Url::set_path`.
    mutating func setPath(_ path: String) {
        segments = FileUrl.parsePathSegments(path)
    }

    // MARK: - conversions

    /// `Url::from_file_path` (Unix).
    static func fromFilePath(_ path: String) -> FileUrl? {
        guard path.hasPrefix("/") else { return nil }
        let raw = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return FileUrl(scheme: "file", rest: "", host: .none,
                       segments: raw.dropFirst().map(encodeSegmentForPush),
                       query: nil, fragment: nil)
    }

    /// `Url::to_file_path` (Unix): no authority, percent-decoded path.
    /// Returns nil for non-UTF-8 results (upstream yields a raw-bytes
    /// `PathBuf`; `AbsolutePathBuf` is UTF-8 — documented gap).
    func toFilePath() -> String? {
        switch host {
        case .none, .empty:
            break
        case .name(let name):
            guard name.isEmpty || name == "localhost" else { return nil }
        }
        let bytes = urlDecodeBinary(Array(path.utf8))
        return String(bytes: bytes, encoding: .utf8)
    }
}

extension FileUrl: CustomStringConvertible {
    public var description: String {
        asString
    }
}
