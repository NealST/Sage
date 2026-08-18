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
import TreeSitterJSON
import TreeSitterJava
import TreeSitterJavaScript
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
        return configCache.value(for: normalized, creating: {
            try? LanguageConfiguration(entry.language, name: entry.name)
        })
    }

    /// Maps common language identifiers to tree-sitter language functions.
    static let languageMap: [String: LanguageEntry] = {
        var map: [String: LanguageEntry] = [:]

        let entries: [(keys: [String], language: Language, name: String)] = [
            (["swift"], Language(tree_sitter_swift()), "Swift"),
            (["python", "py"], Language(tree_sitter_python()), "Python"),
            (["javascript", "js"], Language(tree_sitter_javascript()), "JavaScript"),
            (["typescript", "ts"], Language(tree_sitter_typescript()), "TypeScript"),
            (["tsx"], Language(tree_sitter_tsx()), "TSX"),
            (["rust", "rs"], Language(tree_sitter_rust()), "Rust"),
            (["go", "golang"], Language(tree_sitter_go()), "Go"),
            (["c"], Language(tree_sitter_c()), "C"),
            (["cpp", "c++", "cxx", "cc"], Language(tree_sitter_cpp()), "CPP"),
            (["json"], Language(tree_sitter_json()), "JSON"),
            (["html", "htm"], Language(tree_sitter_html()), "HTML"),
            (["css"], Language(tree_sitter_css()), "CSS"),
            (["bash", "sh", "shell", "zsh"], Language(tree_sitter_bash()), "Bash"),
            (["ruby", "rb"], Language(tree_sitter_ruby()), "Ruby"),
            (["java"], Language(tree_sitter_java()), "Java"),
            (["kotlin", "kt"], Language(tree_sitter_kotlin()), "Kotlin"),
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
