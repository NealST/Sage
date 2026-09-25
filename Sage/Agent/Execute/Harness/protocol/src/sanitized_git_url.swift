//
//  sanitized_git_url.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/sanitized_git_url.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A git remote URL with authentication credentials removed. Upstream parses
//  with `gix-url`; this port recognizes the same two shapes (scheme URLs and
//  SCP-style `[user@]host:path`) with `URLComponents` plus a small SCP parser,
//  including the IPv6 fallback for `user@[v6]:path` remotes. Reconstruction
//  works on the original text so percent-encoded repository paths are never
//  decoded and re-encoded.
//

import Foundation

/// A git remote URL with authentication credentials removed.
public struct SanitizedGitUrl: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    private let value: String

    public var asStr: String { value }
    public var description: String { value }

    /// `TryFrom<&str>`. Errors are a static message so embedded secrets never
    /// leak through diagnostics.
    public init(parsing raw: String) throws {
        // Remote helpers wrap another remote, so peel off their prefixes
        // without recursion before passing the address to the Git URL parser.
        var address = raw
        while let split = address.splitOnce("::"),
              !split.head.isEmpty,
              split.head.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") })
        {
            // Helpers can also receive executable command lines containing
            // arbitrary secrets; scan the whole payload once and reject those.
            if address.count == raw.count, split.nested.contains(where: { $0.isWhitespace }) {
                throw SanitizedGitUrlError.invalid
            }
            address = String(split.nested)
        }
        let helperPrefix = String(raw.prefix(raw.count - address.count))
        let original = raw
        let value = address

        // Parse first to recognize both URL and SCP-style remotes and reject
        // malformed inputs before reconstructing the original text.
        let parsed: ParsedGitURL
        if let url = ParsedGitURL.parse(value) {
            parsed = url
        } else {
            // gix mistakes an IPv6 address's first colon for the SCP path
            // separator when a username comes before the bracketed host.
            guard let at = value.firstIndex(of: "@") else {
                throw SanitizedGitUrlError.invalid
            }
            let user = value[value.startIndex..<at]
            let hostAndPath = value[value.index(after: at)...]
            guard hostAndPath.hasPrefix("["),
                  let closeRange = hostAndPath.range(of: "]:") else {
                throw SanitizedGitUrlError.invalid
            }
            let host = hostAndPath[hostAndPath.index(after: hostAndPath.startIndex)..<closeRange.lowerBound]
            let path = hostAndPath[closeRange.upperBound...]
            if user.isEmpty || path.isEmpty {
                throw SanitizedGitUrlError.invalid
            }
            // SCP paths are opaque and can contain characters that URL parsing
            // rejects; validate via a normalized ssh URL.
            guard let ssh = ParsedGitURL.parse("ssh://\(user)@[\(host)]/") else {
                throw SanitizedGitUrlError.invalid
            }
            parsed = ssh
        }

        // SSH's conventional `git` user is a transport identity, not a secret;
        // every other username and all passwords must be removed.
        let preserveSshGitUser = parsed.scheme == "ssh" && parsed.user == "git"

        // Inspect the authority directly because gix treats the complete
        // `file://` authority as its host and does not expose its userinfo.
        // Rebuilding only this part also preserves escaped repository paths.
        if let schemeSplit = value.splitOnce("://") {
            let scheme = schemeSplit.head
            let authorityAndPath = schemeSplit.nested
            let authorityEnd = authorityAndPath.firstIndex(of: "/") ?? authorityAndPath.endIndex
            let authority = authorityAndPath[authorityAndPath.startIndex..<authorityEnd]
            let path = authorityAndPath[authorityEnd...]
            guard let at = authority.lastIndex(of: "@") else {
                self.value = original
                return
            }
            let host = authority[authority.index(after: at)...]
            if preserveSshGitUser && parsed.password == nil {
                self.value = original
                return
            }
            let user = preserveSshGitUser ? "git@" : ""
            self.value = "\(helperPrefix)\(scheme)://\(user)\(host)\(path)"
            return
        }

        // Parsed serialization can alter Git paths, so preserve the exact
        // original representation whenever no credential needs removal.
        if parsed.password == nil && (parsed.user == nil || preserveSshGitUser) {
            self.value = original
            return
        }

        // SCP-style remotes have no URL authority; remove only `user@` and
        // leave the original `host:path` untouched.
        let authorityEnd = value.firstIndex(of: ":") ?? value.endIndex
        guard let userEnd = value[value.startIndex..<authorityEnd].lastIndex(of: "@") else {
            throw SanitizedGitUrlError.invalid
        }
        self.value = helperPrefix + String(value[value.index(after: userEnd)...])
    }
}

/// `invalid git remote URL` — deliberately carries no input text.
public enum SanitizedGitUrlError: Error, Equatable {
    case invalid

    public var localizedDescription: String { "invalid git remote URL" }
}

extension SanitizedGitUrl {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        do {
            try self.init(parsing: raw)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "invalid git remote URL")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension SanitizedGitUrl {
    public static func < (lhs: SanitizedGitUrl, rhs: SanitizedGitUrl) -> Bool {
        lhs.value < rhs.value
    }
}

/// `deserialize_optional_sanitized_git_url`: malformed legacy origins must not
/// prevent the rest of a rollout from loading.
func decodeOptionalSanitizedGitURL<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> SanitizedGitUrl? {
    guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
    return try? SanitizedGitUrl(parsing: raw)
}

/// Minimal recognized shape of a git remote, mirroring the parts of
/// `gix_url::Url` the sanitizer consults.
private struct ParsedGitURL {
    var scheme: String?
    var user: String?
    var password: String?

    static func parse(_ value: String) -> ParsedGitURL? {
        if value.contains("://") {
            guard let components = URLComponents(string: value),
                  let scheme = components.scheme else { return nil }
            return ParsedGitURL(
                scheme: scheme.lowercased(),
                user: components.user,
                password: components.password
            )
        }
        // SCP-style `[user@]host:path` or a plain local path.
        guard let colon = value.firstIndex(of: ":") else {
            return ParsedGitURL(scheme: nil, user: nil, password: nil)
        }
        let authority = value[value.startIndex..<colon]
        let path = value[value.index(after: colon)...]
        // Brackets in the authority mean the first colon belongs to an IPv6
        // literal; the caller's fallback re-validates those remotes.
        if authority.contains("[") || authority.contains("]") { return nil }
        var user: String? = nil
        var host = authority
        if let at = authority.firstIndex(of: "@") {
            user = String(authority[authority.startIndex..<at])
            host = authority[authority.index(after: at)...]
        }
        guard !host.isEmpty, !path.isEmpty else { return nil }
        return ParsedGitURL(scheme: nil, user: user, password: nil)
    }
}

private extension String {
    /// `str::split_once` for the first occurrence of a separator.
    func splitOnce(_ separator: String) -> (head: Substring, nested: Substring)? {
        guard let range = range(of: separator) else { return nil }
        let head = self[startIndex..<range.lowerBound]
        let nested = self[range.upperBound...]
        return (head, nested)
    }
}
