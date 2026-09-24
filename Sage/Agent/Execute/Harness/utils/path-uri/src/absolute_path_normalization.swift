//
//  absolute_path_normalization.swift
//  CodexUtils
//
//  Port of codex-rs/utils/path-uri/src/absolute_path_normalization.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

/// `path_uri_from_segments` (`pub(super)` upstream).
///
/// Builds a `file:` URI from native path segments: `.`/`..` are resolved
/// lexically without escaping the POSIX root or the Windows drive/UNC anchor,
/// a trailing separator is preserved, and a bare Windows drive root gains its
/// canonical trailing empty segment.
func pathUriFromSegments(
    convention: PathConvention,
    host: String?,
    segments: [String]
) -> PathUri? {
    guard var url = try? FileUrl.parse("file:///") else {
        return nil
    }
    if let host {
        guard (try? url.setHost(host)) != nil else {
            return nil
        }
    }
    let anchorDepth = convention == .windows ? 1 : 0
    var depth = 0
    var normalizedSegments: [String] = []
    var hasTrailingSeparator = false
    for segment in segments {
        switch segment {
        case "":
            hasTrailingSeparator = true
        case ".":
            hasTrailingSeparator = false
        case "..":
            hasTrailingSeparator = false
            if depth > anchorDepth {
                normalizedSegments.removeLast()
                depth -= 1
            }
        default:
            normalizedSegments.append(segment)
            depth += 1
            hasTrailingSeparator = false
        }
    }
    if hasTrailingSeparator
        || (convention == .windows && host == nil && depth == anchorDepth) {
        normalizedSegments.append("")
    }
    url.replaceSegments(normalizedSegments)
    return try? PathUri(validating: url)
}
