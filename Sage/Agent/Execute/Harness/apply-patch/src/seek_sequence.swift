//
//  seek_sequence.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/seek_sequence.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

func seekSequence(
    lines: [String],
    pattern: [String],
    start: Int,
    eof: Bool,
    updateFileMode: ApplyPatchFileUpdateMode
) -> Int? {
    if pattern.isEmpty { return start }
    if pattern.count > lines.count { return nil }

    let searchStart: Int
    if eof, lines.count >= pattern.count {
        let eofStart = lines.count - pattern.count
        switch updateFileMode {
        case .normalizeToLf:
            searchStart = eofStart
        case .preserveLineEndings:
            searchStart = max(eofStart, start)
        }
    } else {
        searchStart = start
    }

    let lastStart = lines.count - pattern.count
    guard searchStart <= lastStart else { return nil }

    for index in searchStart...lastStart {
        if Array(lines[index..<(index + pattern.count)]) == pattern {
            return index
        }
    }
    for index in searchStart...lastStart {
        var ok = true
        for (offset, pat) in pattern.enumerated() where lines[index + offset].applyPatchTrimEnd() != pat.applyPatchTrimEnd() {
            ok = false
            break
        }
        if ok { return index }
    }
    for index in searchStart...lastStart {
        var ok = true
        for (offset, pat) in pattern.enumerated()
            where lines[index + offset].trimmingCharacters(in: .whitespaces)
                != pat.trimmingCharacters(in: .whitespaces) {
            ok = false
            break
        }
        if ok { return index }
    }
    for index in searchStart...lastStart {
        var ok = true
        for (offset, pat) in pattern.enumerated()
            where normalizePunctuation(lines[index + offset]) != normalizePunctuation(pat) {
            ok = false
            break
        }
        if ok { return index }
    }
    return nil
}

private func normalizePunctuation(_ value: String) -> String {
    String(
        value.trimmingCharacters(in: .whitespaces).map { character in
            switch character {
            case "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}":
                return Character("-")
            case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}":
                return Character("'")
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}":
                return Character("\"")
            case "\u{00A0}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}",
                 "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}", "\u{202F}", "\u{205F}", "\u{3000}":
                return Character(" ")
            default:
                return character
            }
        }
    )
}
