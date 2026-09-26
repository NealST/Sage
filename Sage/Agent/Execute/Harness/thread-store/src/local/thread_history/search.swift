//
//  search.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_history/search.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request validation (empty `searchTerm`, zero `pageSize`) and JSON
//  `SearchCursor` encode/decode run in memory. SQLite occurrence paging
//  throws until GRDB. App-server `ThreadItem` searchable-text extraction
//  and pulldown-cmark markdown flattening are omitted.
//

import CodexProtocol
import Foundation

private let snippetContextBeforeChars = 48
private let snippetContextAfterChars = 96

struct SearchCursor: Codable, Equatable {
    var threadId: ThreadId
    var searchTerm: String
    var nextRolloutOrdinal: Int64
    var nextOccurrenceIndex: Int
}

func searchLocalThreadOccurrences(
    store: LocalThreadStore,
    params: SearchThreadOccurrencesParams
) throws -> ThreadOccurrenceSearchPage {
    _ = store
    if params.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw ThreadStoreError.invalidRequest("thread/searchOccurrences requires search_term")
    }
    if params.pageSize == 0 {
        throw ThreadStoreError.invalidRequest(
            "thread/searchOccurrences requires page_size greater than zero")
    }
    _ = try parseSearchCursor(
        params.cursor,
        threadId: params.threadId,
        searchTerm: params.searchTerm
    )
    throw paginatedThreadsUnsupported()
}

func parseSearchCursor(
    _ cursor: String?,
    threadId: ThreadId,
    searchTerm: String
) throws -> SearchCursor? {
    guard let cursor else { return nil }
    let cursorValue: SearchCursor
    do {
        cursorValue = try JSONDecoder().decode(SearchCursor.self, from: Data(cursor.utf8))
    } catch {
        throw invalidSearchCursor(cursor)
    }
    if cursorValue.threadId != threadId
        || cursorValue.searchTerm != searchTerm
        || cursorValue.nextRolloutOrdinal < 0
    {
        throw invalidSearchCursor(cursor)
    }
    return cursorValue
}

func serializeCursorForSearch(_ cursor: SearchCursor) throws -> String {
    let encoded: Data
    do {
        encoded = try JSONEncoder().encode(cursor)
    } catch {
        throw threadHistoryError(error)
    }
    guard let token = String(data: encoded, encoding: .utf8) else {
        throw threadHistoryError("cursor is not valid UTF-8")
    }
    return token
}

func invalidSearchCursor(_ cursor: String) -> ThreadStoreError {
    .invalidRequest("invalid cursor: \(cursor)")
}

struct LiteralMatcher {
    var lowercaseNeedle: String

    init(needle: String) {
        lowercaseNeedle = needle.lowercased()
    }

    /// Original UTF-8 byte ranges, matching Rust `find_ranges`.
    func findRanges(text: String, limit: Int) -> [Range<Int>] {
        let lowercaseText = text.lowercased()
        let lowercaseBytes = [UInt8](lowercaseText.utf8)
        let needleBytes = [UInt8](lowercaseNeedle.utf8)
        guard !needleBytes.isEmpty, limit > 0 else { return [] }

        var spans: [(Range<Int>, Range<Int>)] = []
        spans.reserveCapacity(text.count)
        var lowercaseStart = 0
        var originalStart = 0
        for character in text {
            let originalEnd = originalStart + character.utf8.count
            let lowercaseEnd = lowercaseStart + character.lowercased().utf8.count
            spans.append((lowercaseStart..<lowercaseEnd, originalStart..<originalEnd))
            lowercaseStart = lowercaseEnd
            originalStart = originalEnd
        }

        var startSpan = 0
        var endSpan = 0
        var ranges: [Range<Int>] = []
        var pos = 0
        while ranges.count < limit, pos + needleBytes.count <= lowercaseBytes.count {
            if lowercaseBytes[pos..<(pos + needleBytes.count)].elementsEqual(needleBytes) {
                let start = pos
                let end = pos + needleBytes.count
                while startSpan < spans.count, spans[startSpan].0.upperBound <= start {
                    startSpan += 1
                }
                let lastMatched = end > 0 ? end - 1 : 0
                while endSpan < spans.count, spans[endSpan].0.upperBound <= lastMatched {
                    endSpan += 1
                }
                if startSpan < spans.count, endSpan < spans.count {
                    ranges.append(spans[startSpan].1.lowerBound..<spans[endSpan].1.upperBound)
                }
                pos = end
            } else {
                pos += 1
            }
        }
        return ranges
    }
}

func occurrenceInItem(
    turnId: String,
    itemId: String,
    text: String,
    matched: Range<Int>,
    turnCursor: String
) -> StoredThreadOccurrence {
    let snippetStart = charStartBefore(text, byteIndex: matched.lowerBound, charsBefore: snippetContextBeforeChars)
    let snippetEnd = charEndAfter(text, byteIndex: matched.upperBound, charsAfter: snippetContextAfterChars)
    let leadingEllipsis = snippetStart > 0
    let trailingEllipsis = snippetEnd < text.utf8.count
    var snippet = ""
    if leadingEllipsis {
        snippet.append("... ")
    }
    snippet.append(utf8Substring(text, snippetStart..<snippetEnd))
    if trailingEllipsis {
        snippet.append(" ...")
    }
    let snippetMatchStart =
        (leadingEllipsis ? 4 : 0) + utf16Len(utf8Substring(text, snippetStart..<matched.lowerBound))
    let matchLen = utf16Len(utf8Substring(text, matched))
    return StoredThreadOccurrence(
        turnId: turnId,
        itemId: itemId,
        snippet: snippet,
        snippetMatchRange: SearchTextRange(
            start: snippetMatchStart,
            end: snippetMatchStart.addingReportingOverflow(matchLen).partialValue
        ),
        turnCursor: turnCursor
    )
}

func utf16Len(_ text: String) -> UInt32 {
    UInt32(clamping: text.utf16.count)
}

func charStartBefore(_ text: String, byteIndex: Int, charsBefore: Int) -> Int {
    let prefix = utf8Substring(text, 0..<max(byteIndex, 0))
    var starts: [Int] = []
    var byte = 0
    for character in prefix {
        starts.append(byte)
        byte += character.utf8.count
    }
    if charsBefore < starts.count {
        return starts[starts.count - 1 - charsBefore]
    }
    return 0
}

func charEndAfter(_ text: String, byteIndex: Int, charsAfter: Int) -> Int {
    let total = text.utf8.count
    let suffix = utf8Substring(text, min(byteIndex, total)..<total)
    var offset = 0
    var count = 0
    for character in suffix {
        if count == charsAfter {
            return byteIndex + offset
        }
        offset += character.utf8.count
        count += 1
    }
    return total
}

func utf8Substring(_ text: String, _ range: Range<Int>) -> String {
    let bytes = [UInt8](text.utf8)
    let lower = max(0, range.lowerBound)
    let upper = min(bytes.count, range.upperBound)
    guard lower < upper else { return "" }
    return String(decoding: bytes[lower..<upper], as: UTF8.self)
}
