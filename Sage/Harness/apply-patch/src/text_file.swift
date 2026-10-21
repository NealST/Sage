//
//  text_file.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/text_file.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

typealias Replacement = (start: Int, oldCount: Int, newLines: [String])

private enum LineEnding {
    case lf
    case crlf
    case cr

    var value: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }
}

private struct SourceLine {
    var text: String
    var ending: LineEnding?
}

struct SourceFile {
    private var lines: [SourceLine] = []
    private var preferredEnding: LineEnding = .lf

    static func parse(_ contents: String) -> SourceFile {
        var file = SourceFile()
        var preferred: LineEnding?
        var lineStart = contents.startIndex
        var cursor = contents.startIndex

        while cursor < contents.endIndex {
            let character = contents[cursor]
            let ending: LineEnding?
            let endingEnd: String.Index
            if character == "\r" {
                let next = contents.index(after: cursor)
                if next < contents.endIndex, contents[next] == "\n" {
                    ending = .crlf
                    endingEnd = contents.index(after: next)
                } else {
                    ending = .cr
                    endingEnd = next
                }
            } else if character == "\n" {
                ending = .lf
                endingEnd = contents.index(after: cursor)
            } else {
                cursor = contents.index(after: cursor)
                continue
            }
            if preferred == nil { preferred = ending }
            file.lines.append(SourceLine(text: String(contents[lineStart..<cursor]), ending: ending))
            cursor = endingEnd
            lineStart = cursor
        }

        if lineStart < contents.endIndex {
            file.lines.append(SourceLine(text: String(contents[lineStart...]), ending: nil))
        }
        file.preferredEnding = preferred ?? .lf
        return file
    }

    func lineTexts() -> [String] {
        lines.map(\.text)
    }

    mutating func applyReplacements(_ replacements: [Replacement]) {
        var sourceLines = lines.makeIterator()
        var newLines: [SourceLine] = []
        var sourceIndex = 0

        for replacement in replacements {
            let skip = replacement.start - sourceIndex
            for _ in 0..<skip {
                if let line = sourceLines.next() {
                    newLines.append(line)
                }
            }
            for _ in 0..<replacement.oldCount {
                _ = sourceLines.next()
            }
            newLines.append(contentsOf: replacement.newLines.map {
                SourceLine(text: $0, ending: preferredEnding)
            })
            sourceIndex = replacement.start + replacement.oldCount
        }
        while let line = sourceLines.next() {
            newLines.append(line)
        }
        lines = newLines
        for index in lines.indices where lines[index].ending == nil {
            lines[index].ending = preferredEnding
        }
    }

    func contents() -> String {
        var result = ""
        for line in lines {
            result.append(line.text)
            if let ending = line.ending {
                result.append(ending.value)
            }
        }
        return result
    }
}
