//
//  tagged_line_parser.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/tagged_line_parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `pub(crate)` maps to `internal`. `std::mem::take` maps to assignment of
//  `""`. `trim_start`/`trim_end` map to `CharacterSet.whitespaces` trimming
//  (tag lines are ASCII in practice).
//

import Foundation

private extension String {
    /// `str::trim_start` (Unicode whitespace).
    func trimmingLeadingWhitespace() -> String {
        String(drop(while: { $0.isWhitespace }))
    }

    /// `str::trim_end` (Unicode whitespace).
    func trimmingTrailingWhitespace() -> String {
        String(String(reversed().drop(while: { $0.isWhitespace })).reversed())
    }
}

struct TagSpec<T> {
    let open: String
    let close: String
    let tag: T
}

enum TaggedLineSegment<T> {
    case normal(String)
    case tagStart(T)
    case tagDelta(T, String)
    case tagEnd(T)
}

extension TaggedLineSegment: Equatable where T: Equatable {}

/// Stateful line parser that splits input into normal text vs tag blocks.
///
/// The parser buffers each line until it can disprove that the line is a tag,
/// which is required for tags that must appear alone on a line.
final class TaggedLineParser<T: Equatable> {
    private let specs: [TagSpec<T>]
    private var activeTag: T?
    private var detectTag = true
    private var lineBuffer = ""

    init(specs: [TagSpec<T>]) {
        self.specs = specs
    }

    func parse(_ delta: String) -> [TaggedLineSegment<T>] {
        var segments: [TaggedLineSegment<T>] = []
        var run = ""

        for ch in delta {
            if detectTag {
                if !run.isEmpty {
                    pushText(run, &segments)
                    run = ""
                }
                lineBuffer.append(ch)
                if ch == "\n" {
                    finishLine(&segments)
                    continue
                }
                let slug = lineBuffer.trimmingLeadingWhitespace()
                if slug.isEmpty || isTagPrefix(slug) {
                    continue
                }
                let buffered = lineBuffer
                lineBuffer = ""
                detectTag = false
                pushText(buffered, &segments)
                continue
            }

            run.append(ch)
            if ch == "\n" {
                pushText(run, &segments)
                run = ""
                detectTag = true
            }
        }

        if !run.isEmpty {
            pushText(run, &segments)
        }

        return segments
    }

    func finish() -> [TaggedLineSegment<T>] {
        var segments: [TaggedLineSegment<T>] = []
        if !lineBuffer.isEmpty {
            let buffered = lineBuffer
            lineBuffer = ""
            let withoutNewline = buffered.hasSuffix("\n") ? String(buffered.dropLast()) : buffered
            let slug = withoutNewline.trimmingCharacters(in: .whitespaces)

            if let tag = matchOpen(slug), activeTag == nil {
                pushSegment(&segments, .tagStart(tag))
                activeTag = tag
            } else if let tag = matchClose(slug), activeTag == tag {
                pushSegment(&segments, .tagEnd(tag))
                activeTag = nil
            } else {
                pushText(buffered, &segments)
            }
        }
        if let tag = activeTag {
            activeTag = nil
            pushSegment(&segments, .tagEnd(tag))
        }
        detectTag = true
        return segments
    }

    private func finishLine(_ segments: inout [TaggedLineSegment<T>]) {
        let line = lineBuffer
        lineBuffer = ""
        let withoutNewline = line.hasSuffix("\n") ? String(line.dropLast()) : line
        let slug = withoutNewline.trimmingCharacters(in: .whitespaces)

        if let tag = matchOpen(slug), activeTag == nil {
            pushSegment(&segments, .tagStart(tag))
            activeTag = tag
            detectTag = true
            return
        }

        if let tag = matchClose(slug), activeTag == tag {
            pushSegment(&segments, .tagEnd(tag))
            activeTag = nil
            detectTag = true
            return
        }

        detectTag = true
        pushText(line, &segments)
    }

    private func pushText(_ text: String, _ segments: inout [TaggedLineSegment<T>]) {
        if let tag = activeTag {
            pushSegment(&segments, .tagDelta(tag, text))
        } else {
            pushSegment(&segments, .normal(text))
        }
    }

    private func isTagPrefix(_ slug: String) -> Bool {
        let slug = slug.trimmingTrailingWhitespace()
        return specs.contains { $0.open.hasPrefix(slug) || $0.close.hasPrefix(slug) }
    }

    private func matchOpen(_ slug: String) -> T? {
        specs.first { $0.open == slug }?.tag
    }

    private func matchClose(_ slug: String) -> T? {
        specs.first { $0.close == slug }?.tag
    }
}

private func pushSegment<T: Equatable>(
    _ segments: inout [TaggedLineSegment<T>],
    _ segment: TaggedLineSegment<T>
) {
    switch segment {
    case .normal(let delta):
        if delta.isEmpty { return }
        if case .normal(let existing)? = segments.last {
            segments[segments.count - 1] = .normal(existing + delta)
            return
        }
        segments.append(.normal(delta))
    case .tagDelta(let tag, let delta):
        if delta.isEmpty { return }
        if case .tagDelta(let existingTag, let existing)? = segments.last, existingTag == tag {
            segments[segments.count - 1] = .tagDelta(existingTag, existing + delta)
            return
        }
        segments.append(.tagDelta(tag, delta))
    case .tagStart(let tag):
        segments.append(.tagStart(tag))
    case .tagEnd(let tag):
        segments.append(.tagEnd(tag))
    }
}
