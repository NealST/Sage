//
//  platform.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/platform.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Unix `std::os::unix::fs::symlink` is `FileManager.createSymbolicLink`.
//  Windows branches are omitted (platform: macOS).
//

import Foundation

public func createSymlink(
    source: String,
    linkTarget: String,
    destination: String
) throws {
    _ = source
    try FileManager.default.createSymbolicLink(
        atPath: destination,
        withDestinationPath: linkTarget
    )
}
