//
//  seatbelt_daemon.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/seatbelt_daemon.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Mandatory pathname and network protections for privileged daemon sockets.
//

import Foundation

func seatbeltDaemonProtectionPolicy(directory: String) throws -> String {
    let quoted = try jsonQuoted(directory)
    var rules = [
        "(deny file-read* file-write* (literal \(quoted)) (subpath \(quoted)))\n(deny network-outbound (remote unix-socket (subpath \(quoted))))"
    ]
    var ancestor = (directory as NSString).deletingLastPathComponent
    while !ancestor.isEmpty && ancestor != "/" && ancestor != directory {
        let quotedAncestor = try jsonQuoted(ancestor)
        rules.append(
            "(deny file-write-unlink (require-all (vnode-type DIRECTORY) (literal \(quotedAncestor))))"
        )
        let parent = (ancestor as NSString).deletingLastPathComponent
        if parent == ancestor { break }
        ancestor = parent
    }
    if ancestor == "/" {
        let quotedRoot = try jsonQuoted("/")
        rules.append(
            "(deny file-write-unlink (require-all (vnode-type DIRECTORY) (literal \(quotedRoot))))"
        )
    }
    return rules.joined(separator: "\n")
}

func jsonQuoted(_ value: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    guard let encoded = String(data: data, encoding: .utf8) else {
        throw SeatbeltPreparationError.fileSystem("failed to quote \(value)")
    }
    return encoded
}
