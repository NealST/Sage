//
//  windows_glob.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/permissions/windows_glob.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Windows deny-glob scan bounds shared by policy validation and native ACL
//  expansion. `PathConvention` comes from CodexUtils (the protocol crate
//  depends on the utils crates upstream). Slices stay as `Substring`s
//  borrowing the pattern, mirroring the upstream `&'a str` output.
//

import CodexUtils
import Foundation

/// Literal scan root and maximum traversal depth for a Windows deny glob.
public struct WindowsDenyReadGlobScan {
    public let root: Substring
    public let patternSuffix: Substring
    public let maxDepth: Int?

    public init(root: Substring, patternSuffix: Substring, maxDepth: Int?) {
        self.root = root
        self.patternSuffix = patternSuffix
        self.maxDepth = maxDepth
    }
}

/// `windows_deny_read_glob_scan` — plans lexical scan bounds without
/// accessing the controller's filesystem.
public func windowsDenyReadGlobScan(
    pattern: String,
    configuredMaxDepth: Int?
) -> WindowsDenyReadGlobScan {
    let firstGlob = pattern.firstIndex(where: { $0 == "*" || $0 == "?" || $0 == "[" })
        ?? pattern.endIndex
    let literalPrefix = pattern[pattern.startIndex..<firstGlob]
    let root: Substring
    let patternSuffix: Substring
    if let index = literalPrefix.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
        let driveRoot = index > literalPrefix.startIndex
            && literalPrefix[literalPrefix.index(before: index)] == ":"
        let end = (index == literalPrefix.startIndex || driveRoot)
            ? literalPrefix.index(after: index)
            : index
        root = literalPrefix[literalPrefix.startIndex..<end]
        patternSuffix = pattern[pattern.index(after: index)...]
    } else {
        root = "."
        patternSuffix = Substring(pattern)
    }
    let components = PathConvention.windows
        .pathSegments(String(patternSuffix))
        .filter { !$0.isEmpty }
    let maxDepth: Int?
    if components.contains("**") {
        maxDepth = configuredMaxDepth
    } else {
        maxDepth = configuredMaxDepth.map { min($0, components.count) } ?? components.count
    }
    return WindowsDenyReadGlobScan(
        root: root,
        patternSuffix: patternSuffix,
        maxDepth: maxDepth
    )
}
