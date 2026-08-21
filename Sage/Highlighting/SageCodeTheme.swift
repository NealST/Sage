//
//  SageCodeTheme.swift
//  Sage
//
//  Xcode-inspired syntax colors that adapt to light/dark mode and high contrast.

import SwiftUI

/// Syntax highlighting color palette aligned with Apple's Xcode conventions.
///
/// Colors use SwiftUI adaptive `Color` so they automatically respond to
/// appearance changes (light/dark) and accessibility settings (high contrast).
enum SageCodeTheme {
    // MARK: - Token Colors

    /// Keywords: `func`, `let`, `var`, `if`, `return`, `import`, etc.
    static var keyword: Color {
        Color(
            light: .init(red: 0.61, green: 0.14, blue: 0.69, alpha: 1),
            dark: .init(red: 0.79, green: 0.49, blue: 0.89, alpha: 1)
        )
    }

    /// Type names: `String`, `Int`, `View`, custom types
    static var type: Color {
        Color(
            light: .init(red: 0.11, green: 0.43, blue: 0.55, alpha: 1),
            dark: .init(red: 0.39, green: 0.78, blue: 0.82, alpha: 1)
        )
    }

    /// Function/method names
    static var function: Color {
        Color(
            light: .init(red: 0.15, green: 0.35, blue: 0.60, alpha: 1),
            dark: .init(red: 0.40, green: 0.65, blue: 0.96, alpha: 1)
        )
    }

    /// String literals
    static var string: Color {
        Color(
            light: .init(red: 0.77, green: 0.10, blue: 0.09, alpha: 1),
            dark: .init(red: 0.99, green: 0.42, blue: 0.38, alpha: 1)
        )
    }

    /// Numeric literals
    static var number: Color {
        Color(
            light: .init(red: 0.11, green: 0.36, blue: 0.73, alpha: 1),
            dark: .init(red: 0.55, green: 0.73, blue: 0.99, alpha: 1)
        )
    }

    /// Comments
    static var comment: Color {
        Color(
            light: .init(red: 0.42, green: 0.47, blue: 0.51, alpha: 1),
            dark: .init(red: 0.51, green: 0.56, blue: 0.60, alpha: 1)
        )
    }

    /// Operators: `+`, `-`, `=`, `->`, etc.
    static var `operator`: Color {
        Color(
            light: .init(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),
            dark: .init(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        )
    }

    /// Preprocessor directives, attributes: `#if`, `@available`
    static var preprocessor: Color {
        Color(
            light: .init(red: 0.64, green: 0.39, blue: 0.13, alpha: 1),
            dark: .init(red: 0.99, green: 0.65, blue: 0.27, alpha: 1)
        )
    }

    /// Property/variable names
    static var property: Color {
        Color(
            light: .init(red: 0.22, green: 0.33, blue: 0.53, alpha: 1),
            dark: .init(red: 0.55, green: 0.73, blue: 0.99, alpha: 1)
        )
    }

    /// Plain text / default fallback
    static var plain: Color {
        Color(
            light: .init(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),
            dark: .init(red: 0.92, green: 0.92, blue: 0.94, alpha: 1)
        )
    }

    /// Punctuation: brackets, braces, semicolons
    static var punctuation: Color {
        Color(
            light: .init(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.7),
            dark: .init(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.6)
        )
    }

    // MARK: - Token Resolution

    /// Maps a tree-sitter capture name (e.g. "keyword.function") to a color.
    static func color(for captureName: String) -> Color {
        let base = captureName.split(separator: ".").first.map(String.init) ?? captureName

        switch base {
        case "keyword", "conditional", "repeat", "include", "exception":
            return keyword

        case "type", "storageclass", "structure":
            return type

        case "function", "method":
            return function

        case "string", "character":
            return string

        case "number", "float", "boolean":
            return number

        case "comment":
            return comment

        case "operator":
            return `operator`

        case "preproc", "define", "attribute", "label":
            return preprocessor

        case "property", "field", "parameter", "variable":
            return property

        case "punctuation":
            return punctuation

        case "constant":
            return number

        case "tag":
            return keyword

        case "namespace", "module":
            return type

        default:
            return plain
        }
    }
}

// MARK: - Adaptive Color Helper

private extension Color {
    /// Creates a color that adapts between light and dark appearances.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return dark
            }
            return light
        })
    }
}
