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
///
/// Default actor isolation is MainActor; highlighting is `nonisolated` so
/// parse + cache fill can run off the expand path.
nonisolated struct TreeSitterCodeHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        Text(Self.attributedString(code: code, language: language))
    }

    /// Parse on a utility queue and pin the result so the first expand
    /// of a tool chip does not hitch on the main thread.
    static func preheat(code: String, language: String?) async {
        guard let language, languageConfig(for: language) != nil else { return }
        let key = HighlightCache.Key(language: language, code: code)
        if HighlightRuntime.highlightCache.contains(key) { return }
        let snapshot = code
        let lang = language
        let attributed = await Task.detached(priority: .utility) {
            Self.computeAttributedString(code: snapshot, language: lang)
        }.value
        HighlightRuntime.highlightCache.store(key, attributed)
    }
}

// MARK: - Highlighting Engine

private nonisolated extension TreeSitterCodeHighlighter {
    static func attributedString(code: String, language: String?) -> AttributedString {
        let key = HighlightCache.Key(language: language ?? "", code: code)
        if let cached = HighlightRuntime.highlightCache.value(for: key) {
            return cached
        }
        let computed = computeAttributedString(code: code, language: language)
        HighlightRuntime.highlightCache.store(key, computed)
        return computed
    }

    static func computeAttributedString(code: String, language: String?) -> AttributedString {
        var plain = AttributedString(code)
        plain.foregroundColor = SageCodeTheme.plain
        guard let language, let config = languageConfig(for: language) else {
            return plain
        }
        do {
            let highlights = try highlight(code: code, config: config)
            return buildAttributedString(from: code, highlights: highlights)
        } catch {
            return plain
        }
    }

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

    /// One `AttributedString` instead of concatenating a `Text` per token —
    /// a medium file used to allocate thousands of views on expand.
    static func buildAttributedString(from code: String, highlights: [NamedRange]) -> AttributedString {
        var result = AttributedString(code)
        result.foregroundColor = SageCodeTheme.plain
        guard !highlights.isEmpty else { return result }

        for namedRange in highlights {
            guard let stringRange = Range(namedRange.range, in: code),
                  let attrRange = Range(stringRange, in: result)
            else { continue }
            result[attrRange].foregroundColor = SageCodeTheme.color(for: namedRange.name)
        }
        return result
    }
}

// MARK: - Language Registry

private nonisolated extension TreeSitterCodeHighlighter {
    /// Resolves a language identifier (from markdown fence info) to a tree-sitter configuration.
    static func languageConfig(for identifier: String) -> LanguageConfiguration? {
        let normalized = identifier.lowercased().trimmingCharacters(in: .whitespaces)

        guard let entry = languageMap[normalized] else {
            return nil
        }

        return HighlightRuntime.configCache.value(for: normalized) {
            configuration(for: entry)
        }
    }

    static func configuration(for entry: LanguageEntry) -> LanguageConfiguration? {
        if let bundleName = entry.bundleName,
           let config = try? LanguageConfiguration(entry.language, name: entry.name, bundleName: bundleName) {
            return config
        }
        if let config = try? LanguageConfiguration(entry.language, name: entry.name) {
            return config
        }
        if let fallback = entry.fallbackBundleName {
            return try? LanguageConfiguration(
                entry.language,
                name: entry.name,
                bundleName: fallback
            )
        }
        return nil
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
            // tree-sitter-typescript ships TSX in the same package. The
            // default bundle heuristic looks for TreeSitterTSX_TreeSitterTSX,
            // which does not exist — queries live under the TypeScript package.
            LanguageMapSeed(
                keys: ["tsx", "typescriptreact", "jsx"],
                language: Language(tree_sitter_tsx()),
                name: "TSX",
                bundleName: "TreeSitterTypeScript_TreeSitterTSX",
                fallbackBundleName: "TreeSitterTypeScript_TreeSitterTypeScript"
            ),
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
            let langEntry = LanguageEntry(
                language: entry.language,
                name: entry.name,
                bundleName: entry.bundleName,
                fallbackBundleName: entry.fallbackBundleName
            )
            for key in entry.keys {
                map[key] = langEntry
            }
        }

        return map
    }()
}

// MARK: - Supporting Types

private nonisolated struct LanguageEntry: @unchecked Sendable {
    let language: Language
    let name: String
    var bundleName: String?
    var fallbackBundleName: String?
}

private nonisolated struct LanguageMapSeed: @unchecked Sendable {
    let keys: [String]
    let language: Language
    let name: String
    var bundleName: String?
    var fallbackBundleName: String?
}

/// Thread-safe cache for language configurations.
private nonisolated final class ConfigCache: @unchecked Sendable {
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

/// Bounded result cache so expanding the same chip is a dictionary lookup.
private nonisolated final class HighlightCache: @unchecked Sendable {
    struct Key: Hashable {
        let language: String
        let length: Int
        let hash: Int

        init(language: String, code: String) {
            self.language = language.lowercased()
            self.length = code.count
            self.hash = code.hashValue
        }
    }

    private var cache: [Key: AttributedString] = [:]
    private var order: [Key] = []
    private let lock = NSLock()
    private let limit = 24

    func contains(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[key] != nil
    }

    func value(for key: Key) -> AttributedString? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func store(_ key: Key, _ value: AttributedString) {
        lock.lock()
        defer { lock.unlock() }
        if cache[key] == nil {
            order.append(key)
        }
        cache[key] = value
        while order.count > limit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}

private nonisolated enum HighlightRuntime {
    static let configCache = ConfigCache()
    static let highlightCache = HighlightCache()
}
