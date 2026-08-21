//
//  TreeSitterHighlighter.swift
//  Sage
//
//  Tree-sitter based syntax highlighter that integrates with MarkdownUI's
//  CodeSyntaxHighlighter protocol.

import MarkdownUI
import SwiftTreeSitter
import SwiftUI

// Language parser imports — each provides a `tree_sitter_<lang>()` function.
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript

// MARK: - CodeSyntaxHighlighter Conformance

/// A `CodeSyntaxHighlighter` that uses tree-sitter for AST-accurate highlighting.
///
/// Produces SwiftUI `Text` with Xcode-style colors via `SageCodeTheme`.
/// Falls back to plain monospaced text for unsupported languages.
struct TreeSitterCodeHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        guard let language, let config = Self.languageConfig(for: language) else {
            return Text(code).foregroundStyle(SageCodeTheme.plain)
        }

        do {
            let highlights = try Self.highlight(code: code, config: config)
            return Self.buildText(from: code, highlights: highlights)
        } catch {
            return Text(code).foregroundStyle(SageCodeTheme.plain)
        }
    }
}

// MARK: - Highlighting Engine

private extension TreeSitterCodeHighlighter {
    /// Parses code and returns highlight ranges using tree-sitter.
    static func highlight(code: String, config: LanguageConfiguration) throws -> [NamedRange] {
        let parser = Parser()
        try parser.setLanguage(config.language)

        guard let tree = parser.parse(code) else {
            return []
        }

        guard let query = config.queries[.highlights] else {
            return []
        }

        let cursor = query.execute(in: tree)
        let context = Predicate.Context(string: code)
        return cursor.resolve(with: context).highlights()
    }

    /// Builds a composed SwiftUI `Text` from source code and highlight ranges.
    static func buildText(from code: String, highlights: [NamedRange]) -> Text {
        guard !highlights.isEmpty else {
            return Text(code).foregroundStyle(SageCodeTheme.plain)
        }

        let nsString = code as NSString
        var result = Text("")
        var lastEnd = 0

        for namedRange in highlights {
            let range = namedRange.range

            // Add any unhighlighted gap before this range
            if range.location > lastEnd {
                let gapRange = NSRange(location: lastEnd, length: range.location - lastEnd)
                let gap = nsString.substring(with: gapRange)
                result = Text("\(result)\(Text(gap).foregroundStyle(SageCodeTheme.plain))")
            }

            // Add the highlighted token
            let token = nsString.substring(with: range)
            let color = SageCodeTheme.color(for: namedRange.name)
            result = Text("\(result)\(Text(token).foregroundStyle(color))")

            lastEnd = range.location + range.length
        }

        // Add any trailing unhighlighted text
        if lastEnd < nsString.length {
            let trailingRange = NSRange(location: lastEnd, length: nsString.length - lastEnd)
            let trailing = nsString.substring(with: trailingRange)
            result = Text("\(result)\(Text(trailing).foregroundStyle(SageCodeTheme.plain))")
        }

        return result
    }
}

// MARK: - Language Registry

private extension TreeSitterCodeHighlighter {
    /// Resolves a language identifier (from markdown fence info) to a tree-sitter configuration.
    static func languageConfig(for identifier: String) -> LanguageConfiguration? {
        let normalized = identifier.lowercased().trimmingCharacters(in: .whitespaces)

        guard let entry = languageMap[normalized] else {
            return nil
        }

        // Cache configurations to avoid repeated bundle lookups
        return configCache.value(for: normalized) {
            try? LanguageConfiguration(entry.language, name: entry.name)
        }
    }

    /// Maps common language identifiers to tree-sitter language functions.
    static let languageMap: [String: LanguageEntry] = {
        var map: [String: LanguageEntry] = [:]

        let entries: [LanguageMapSeed] = [
            LanguageMapSeed(keys: ["swift"], language: Language(tree_sitter_swift()), name: "Swift"),
            LanguageMapSeed(keys: ["python", "py"], language: Language(tree_sitter_python()), name: "Python"),
            LanguageMapSeed(
                keys: ["javascript", "js"],
                language: Language(tree_sitter_javascript()),
                name: "JavaScript"
            ),
            LanguageMapSeed(
                keys: ["typescript", "ts"],
                language: Language(tree_sitter_typescript()),
                name: "TypeScript"
            ),
            LanguageMapSeed(keys: ["tsx"], language: Language(tree_sitter_tsx()), name: "TSX"),
            LanguageMapSeed(keys: ["rust", "rs"], language: Language(tree_sitter_rust()), name: "Rust"),
            LanguageMapSeed(keys: ["go", "golang"], language: Language(tree_sitter_go()), name: "Go"),
            LanguageMapSeed(keys: ["c"], language: Language(tree_sitter_c()), name: "C"),
            LanguageMapSeed(
                keys: ["cpp", "c++", "cxx", "cc"],
                language: Language(tree_sitter_cpp()),
                name: "CPP"
            ),
            LanguageMapSeed(keys: ["json"], language: Language(tree_sitter_json()), name: "JSON"),
            LanguageMapSeed(keys: ["html", "htm"], language: Language(tree_sitter_html()), name: "HTML"),
            LanguageMapSeed(keys: ["css"], language: Language(tree_sitter_css()), name: "CSS"),
            LanguageMapSeed(
                keys: ["bash", "sh", "shell", "zsh"],
                language: Language(tree_sitter_bash()),
                name: "Bash"
            ),
            LanguageMapSeed(keys: ["ruby", "rb"], language: Language(tree_sitter_ruby()), name: "Ruby"),
            LanguageMapSeed(keys: ["java"], language: Language(tree_sitter_java()), name: "Java"),
            LanguageMapSeed(keys: ["kotlin", "kt"], language: Language(tree_sitter_kotlin()), name: "Kotlin"),
        ]

        for entry in entries {
            let langEntry = LanguageEntry(language: entry.language, name: entry.name)
            for key in entry.keys {
                map[key] = langEntry
            }
        }

        return map
    }()
}

// MARK: - Supporting Types

private struct LanguageEntry {
    let language: Language
    let name: String
}

private struct LanguageMapSeed {
    let keys: [String]
    let language: Language
    let name: String
}

/// Thread-safe cache for language configurations.
private final class ConfigCache: @unchecked Sendable {
    private var cache: [String: LanguageConfiguration] = [:]
    private let lock = NSLock()

    func value(for key: String, creating factory: () -> LanguageConfiguration?) -> LanguageConfiguration? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            return cached
        }

        guard let config = factory() else { return nil }
        cache[key] = config
        return config
    }
}

private let configCache = ConfigCache()
