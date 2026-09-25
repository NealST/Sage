//
//  executable_name.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/executable_name.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  macOS uses the Unix branch (identity). The Windows suffix strip is
//  compiled out the same way `cfg!(windows)` is upstream.
//

import Foundation

func executableLookupKey(_ raw: String) -> String {
    raw
}

func executablePathLookupKey(_ path: String) -> String? {
    let name = (path as NSString).lastPathComponent
    return name.isEmpty ? nil : executableLookupKey(name)
}
