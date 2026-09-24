//
//  inline_hidden_tag.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/inline_hidden_tag.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Rust byte offsets (`str::find`, `drain(..n)`) map to UTF-8-view offsets;
//  every cut point is a char boundary by construction (matches are full
//  delimiters, and `longestSuffixPrefixLen` only yields needle char
//  boundaries). `assert!` maps to `precondition`; the two `should_panic`
//  constructor tests are not ported (XCTest cannot trap on `precondition`).
//

import Foundation

/// One hidden inline tag extracted by `InlineHiddenTagParser`.
public struct ExtractedInlineTag<T> {
    public let tag: T
    public let content: String
}

extension ExtractedInlineTag: Equatable where T: Equatable {}

/// Literal tag specification used by `InlineHiddenTagParser`.
public struct InlineTagSpec<T> {
    public let tag: T
    public let open: String
    public let close: String

    public init(tag: T, open: String, close: String) {
        self.tag = tag
        self.open = open
        self.close = close
    }
}

extension InlineTagSpec: Equatable where T: Equatable {}

private struct ActiveTag<T> {
    let tag: T
    let close: String
    var content: String
}

/// Generic streaming parser that hides configured inline tags and extracts
/// their contents.
///
/// Example:
/// - input: `hello <oai-mem-citation>doc A</oai-mem-citation> world`
/// - visible output: `hello  world`
/// - extracted: `["doc A"]`
///
/// Matching is literal and non-nested. If EOF is reached while a tag is still
/// open, the parser auto-closes it and returns the buffered content as
/// extracted data.
public final class InlineHiddenTagParser<T: Equatable> {
    private let specs: [InlineTagSpec<T>]
    private var pending: String = ""
    private var active: ActiveTag<T>?

    /// Create a parser for one or more hidden inline tags.
    public init(specs: [InlineTagSpec<T>]) {
        precondition(
            !specs.isEmpty,
            "InlineHiddenTagParser requires at least one tag spec"
        )
        for spec in specs {
            precondition(
                !spec.open.isEmpty,
                "InlineHiddenTagParser requires non-empty open delimiters"
            )
            precondition(
                !spec.close.isEmpty,
                "InlineHiddenTagParser requires non-empty close delimiters"
            )
        }
        self.specs = specs
    }

    /// Byte offset of `index` in `s`.
    private func byteOffset(of index: String.Index, in s: String) -> Int {
        s.utf8.distance(from: s.utf8.startIndex, to: index)
    }

    /// `&s[..n]` by UTF-8 byte count (n is a char boundary by construction).
    private func prefixBytes(_ s: String, _ n: Int) -> Substring {
        let end = s.utf8.index(s.utf8.startIndex, offsetBy: n)
        return s[..<end]
    }

    /// `s.drain(..n)` by UTF-8 byte count.
    private func dropBytes(_ s: inout String, _ n: Int) {
        let start = s.utf8.index(s.utf8.startIndex, offsetBy: n)
        s = String(s[start...])
    }

    /// `(byte_pos, spec_idx)` of the next open delimiter, breaking ties by
    /// longest opener then spec order (`min_by` upstream).
    private func findNextOpen() -> (Int, Int)? {
        var best: (pos: Int, len: Int, idx: Int)?
        for (idx, spec) in specs.enumerated() {
            guard let range = pending.range(of: spec.open) else { continue }
            let pos = byteOffset(of: range.lowerBound, in: pending)
            let len = spec.open.utf8.count
            if let current = best {
                let better = pos < current.pos
                    || (pos == current.pos && len > current.len)
                    || (pos == current.pos && len == current.len && idx < current.idx)
                if better {
                    best = (pos, len, idx)
                }
            } else {
                best = (pos, len, idx)
            }
        }
        return best.map { ($0.0, $0.2) }
    }

    private func maxOpenPrefixSuffixLen() -> Int {
        specs.map { longestSuffixPrefixLen(pending, $0.open) }.max() ?? 0
    }

    private func pushVisiblePrefix(
        _ out: inout StreamTextChunk<ExtractedInlineTag<T>>,
        _ pending: Substring
    ) {
        if !pending.isEmpty {
            out.visibleText += pending
        }
    }

    private func drainVisibleToSuffixMatch(
        _ out: inout StreamTextChunk<ExtractedInlineTag<T>>,
        keepSuffixLen: Int
    ) {
        let take = pending.utf8.count - keepSuffixLen // saturating_sub: keep <= len
        if take == 0 {
            return
        }
        pushVisiblePrefix(&out, prefixBytes(pending, take))
        dropBytes(&pending, take)
    }
}

extension InlineHiddenTagParser: StreamTextParser {
    public func pushStr(_ chunk: String) -> StreamTextChunk<ExtractedInlineTag<T>> {
        pending += chunk
        var out = StreamTextChunk<ExtractedInlineTag<T>>()

        while true {
            if let close = active?.close {
                if let closeRange = pending.range(of: close) {
                    let closeIdx = byteOffset(of: closeRange.lowerBound, in: pending)
                    let finished = active!
                    active = nil
                    out.extracted.append(ExtractedInlineTag(
                        tag: finished.tag,
                        content: finished.content + prefixBytes(pending, closeIdx)
                    ))
                    dropBytes(&pending, closeIdx + close.utf8.count)
                    continue
                }

                let keep = longestSuffixPrefixLen(pending, close)
                let take = pending.utf8.count - keep
                if take > 0 {
                    active?.content += prefixBytes(pending, take)
                    dropBytes(&pending, take)
                }
                break
            }

            if let (openIdx, specIdx) = findNextOpen() {
                pushVisiblePrefix(&out, prefixBytes(pending, openIdx))
                let spec = specs[specIdx]
                dropBytes(&pending, openIdx + spec.open.utf8.count)
                active = ActiveTag(tag: spec.tag, close: spec.close, content: "")
                continue
            }

            let keep = maxOpenPrefixSuffixLen()
            drainVisibleToSuffixMatch(&out, keepSuffixLen: keep)
            break
        }

        return out
    }

    public func finish() -> StreamTextChunk<ExtractedInlineTag<T>> {
        var out = StreamTextChunk<ExtractedInlineTag<T>>()

        if let finished = active {
            active = nil
            var content = finished.content
            if !pending.isEmpty {
                content += pending
                pending = ""
            }
            out.extracted.append(ExtractedInlineTag(tag: finished.tag, content: content))
            return out
        }

        if !pending.isEmpty {
            out.visibleText += pending
            pending = ""
        }

        return out
    }
}

/// `longest_suffix_prefix_len`: longest `k < needle.len` at a char boundary
/// of `needle` such that `s` ends with `needle[..k]`.
private func longestSuffixPrefixLen(_ s: String, _ needle: String) -> Int {
    let sBytes = Array(s.utf8)
    let needleBytes = Array(needle.utf8)
    let max = min(sBytes.count, needleBytes.count - 1)
    guard max >= 1 else { return 0 }
    for k in (1 ... max).reversed() {
        // `needle.is_char_boundary(k)`: the byte at k is not a UTF-8
        // continuation byte.
        guard needleBytes[k] & 0xC0 != 0x80 else { continue }
        if sBytes.suffix(k).elementsEqual(needleBytes.prefix(k)) {
            return k
        }
    }
    return 0
}
