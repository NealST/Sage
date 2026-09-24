//
//  config_path.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-uri/src/config_path.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Resolve filesystem denial paths with the existing URI parser and lexical
//  join. Reject ambiguous or lossy representations before rendering security
//  constraints.
//

import Foundation

extension PathUri {
    /// Resolves configuration text using only the supplied convention, base,
    /// and home (`resolve_config_path`). Home-relative inputs require a home;
    /// other relative inputs require a base.
    public static func resolveConfigPath(
        input: String,
        convention: PathConvention,
        base: PathUri?,
        userHomeDir: PathUri?
    ) throws -> String {
        try resolveConfigPathUri(
            input: input,
            convention: convention,
            base: base,
            userHomeDir: userHomeDir
        )
        .toConfigPathString(convention: convention)
    }

    /// Resolves and validates configuration text as a URI using only
    /// supplied path facts (`resolve_config_path_uri`). Normalizes trailing
    /// separators while preserving the path's root.
    public static func resolveConfigPathUri(
        input: String,
        convention: PathConvention,
        base: PathUri?,
        userHomeDir: PathUri?
    ) throws -> PathUri {
        try validateConfigPathText(input, convention: convention)
        let path = LegacyAppPathString.fromString(input)
        let resolved: PathUri
        if convention.homeRelativeSuffix(input) != nil {
            guard let home = userHomeDir else {
                throw LegacyAppPathStringError.missingHomeDirectory(path: input)
            }
            try home.validateConfigPath(convention: convention)
            if containsGlobMetacharacter(input) {
                try home.validateGlobDirectory(convention: convention)
            }
            resolved = try path.resolveAgainst(cwd: home, userHomeDir: home)
        } else {
            do {
                resolved = try path.toPathUri(convention)
            } catch {
                guard let base else {
                    throw error
                }
                try base.validateConfigPath(convention: convention)
                if containsGlobMetacharacter(input) {
                    try base.validateGlobDirectory(convention: convention)
                }
                resolved = try path.resolveAgainst(cwd: base, userHomeDir: nil)
            }
        }
        try resolved.validateConfigPath(convention: convention)
        // Config paths historically omit trailing separators except at a root.
        do {
            return try resolved.join(".")
        } catch let error as PathUriParseError {
            throw LegacyAppPathStringError.pathUri(error)
        }
    }

    /// Renders an already resolved configuration path with legacy root
    /// separators (`to_config_path_string`).
    public func toConfigPathString(convention: PathConvention) throws -> String {
        var rendered = try LegacyAppPathString.fromPathUri(self, convention: convention)
            .intoString()
        if url.hostStr != nil && parent() == nil {
            rendered.append("\\")
        }
        return rendered
    }

    /// Checks that a literal directory can be inserted into a glob unchanged
    /// (`validate_glob_directory`). Rejects metacharacters instead of turning
    /// directory names into patterns. POSIX backslashes would escape the
    /// following pattern character.
    public func validateGlobDirectory(convention: PathConvention) throws {
        try validateConfigPath(convention: convention)
        let path = try LegacyAppPathString.fromPathUri(self, convention: convention).intoString()
        if containsGlobMetacharacter(path) || (convention == .posix && path.contains("\\")) {
            throw LegacyAppPathStringError.unsupportedConfigPath(path: path, convention: convention)
        }
    }

    /// Checks that a resolved configuration URI has a lossless native
    /// spelling in the owning executor's convention (`validate_config_path`).
    /// Opaque and ambiguous paths fail.
    public func validateConfigPath(convention: PathConvention) throws {
        guard inferPathConvention() == convention else {
            throw LegacyAppPathStringError.incompatibleConvention(
                path: description,
                convention: convention
            )
        }
        let bytes = decodedPathBytes()
        guard lexicalDepth() != nil,
              !bytes.contains(0),
              String(bytes: bytes, encoding: .utf8) != nil else {
            throw LegacyAppPathStringError.pathUri(.invalidFileUriPath(path: description))
        }
        try PathUri.validateConfigPathText(
            LegacyAppPathString.fromPathUri(self, convention: convention).asStr(),
            convention: convention
        )
    }

    /// Validates native configuration text without resolving paths or glob
    /// syntax (`validate_config_path_text`). Rejects spellings that could
    /// change targets during later native conversion.
    public static func validateConfigPathText(
        _ input: String,
        convention: PathConvention
    ) throws {
        let namespaceAlias = normalizeWindowsDevicePath(input)
        let nativeInput = namespaceAlias ?? input
        let hasWindowsComponentColon = convention == .windows
            && convention.pathSegments(nativeInput).enumerated().contains { index, segment in
                let bytes = Array(segment.utf8)
                let stripped: String
                if index == 0,
                   let first = bytes.first,
                   isAsciiAlpha(first),
                   bytes.count > 1,
                   bytes[1] == UInt8(ascii: ":") {
                    stripped = String(segment.dropFirst(2))
                } else {
                    stripped = segment
                }
                return stripped.contains(":")
            }
        let mixedHomeSeparators = convention == .windows
            && (convention.homeRelativeSuffix(input).map { suffix in
                (suffix.hasPrefix("/")
                    && suffix.drop(while: { $0 == "/" }).hasPrefix("\\"))
                    || (suffix.hasPrefix("\\")
                        && suffix.drop(while: { $0 == "\\" }).hasPrefix("/"))
            } ?? false)
        let nativeBytes = Array(nativeInput.utf8)
        let bareWindowsDrive = convention == .windows
            && nativeBytes.count == 2
            && isAsciiAlpha(nativeBytes[0])
            && nativeBytes[1] == UInt8(ascii: ":")
        if input.contains("\0")
            || hasWindowsComponentColon
            || mixedHomeSeparators
            || bareWindowsDrive {
            throw LegacyAppPathStringError.unsupportedConfigPath(
                path: input,
                convention: convention
            )
        }
    }
}

/// `contains_glob_metacharacter`.
private func containsGlobMetacharacter(_ path: String) -> Bool {
    path.contains { character in
        character == "*" || character == "?" || character == "["
            || character == "]" || character == "{" || character == "}"
    }
}
