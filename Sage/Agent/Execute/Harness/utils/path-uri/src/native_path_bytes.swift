//
//  native_path_bytes.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-uri/src/native_path_bytes.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

extension PathUri {
    /// Resolves a native path stored as bytes, using this URI's path
    /// convention (`join_native_bytes`).
    ///
    /// UTF-8 paths follow `join`. Non-UTF-8 POSIX names are preserved
    /// losslessly, including when the filesystem is on another host. Invalid
    /// UTF-8 Windows paths, null bytes, and opaque base URIs are rejected.
    public func joinNativeBytes(_ path: [UInt8]) throws -> PathUri {
        if let path = String(bytes: path, encoding: .utf8) {
            return try join(path)
        }
        guard inferPathConvention() == .posix,
              opaqueFallbackBytes() == nil,
              !path.contains(0) else {
            throw PathUriParseError.invalidFileUriPath(path: description)
        }
        var segments: [String]
        if path.first == UInt8(ascii: "/") {
            segments = []
        } else {
            segments = encodedPath()
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
        }
        // `slice::split` semantics: empty input yields one empty component.
        var components: [[UInt8]] = [[]]
        for byte in path {
            if byte == UInt8(ascii: "/") {
                components.append([])
            } else {
                components[components.count - 1].append(byte)
            }
        }
        for component in components {
            if component.isEmpty || component == [UInt8(ascii: ".")] {
                continue
            }
            if component == [UInt8(ascii: "."), UInt8(ascii: ".")] {
                if !segments.isEmpty {
                    segments.removeLast()
                }
                continue
            }
            segments.append(urlEncodeBinary(component))
        }
        var url = toUrl()
        url.setPath("/" + segments.joined(separator: "/"))
        let uri = try PathUri(validating: url)
        guard uri.inferPathConvention() == .posix else {
            throw PathUriParseError.invalidFileUriPath(path: uri.description)
        }
        return uri
    }
}
