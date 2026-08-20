//
//  MarkdownPresentation.swift
//  Sage
//
//  Presentation-only transforms for MarkdownUI (does not mutate stored transcript).

import Foundation

nonisolated enum MarkdownPresentation {
    /// Softens completed GFM task items for display by wrapping their text in
    /// strikethrough. Skips fenced code blocks and lines already struck through.
    ///
    /// MarkdownUI only exposes completion on the checkbox marker, so text styling
    /// has to happen before parse.
    static func softenCompletedTasks(in markdown: String) -> String {
        guard markdown.contains("[x]") || markdown.contains("[X]") else { return markdown }

        var inFence = false
        var lines: [String] = []

        markdown.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                lines.append(line)
                return
            }
            if inFence {
                lines.append(line)
                return
            }
            lines.append(softenCompletedTaskLine(line))
        }

        var result = lines.joined(separator: "\n")
        if markdown.hasSuffix("\n"), !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    private static func softenCompletedTaskLine(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\s*(?:[-*+]|\d+\.)\s+)\[([xX])\](\s+)(.*)$"#
        ) else {
            return line
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges == 5,
              let prefixRange = Range(match.range(at: 1), in: line),
              let markRange = Range(match.range(at: 2), in: line),
              let gapRange = Range(match.range(at: 3), in: line),
              let textRange = Range(match.range(at: 4), in: line)
        else {
            return line
        }

        let text = String(line[textRange])
        guard !text.isEmpty else { return line }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("~~"), trimmed.hasSuffix("~~"), trimmed.count >= 4 {
            return line
        }

        let prefix = String(line[prefixRange])
        let mark = String(line[markRange])
        let gap = String(line[gapRange])
        return "\(prefix)[\(mark)]\(gap)~~\(text)~~"
    }
}
