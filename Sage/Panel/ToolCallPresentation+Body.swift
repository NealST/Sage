//
//  ToolCallPresentation+Body.swift
//  Sage
//

import Foundation

extension ToolCallPresentation {
    static func body(
        name: String,
        args: [String: JSONValue],
        policy: PathGuard.Policy
    ) -> Body {
        switch name {
        case "write_text_file":
            return writeFileBody(args, policy: policy)

        case "read_text_file":
            return readFileBody(args, policy: policy)

        case "run_shell_command":
            return shellBody(args, policy: policy)

        case "set_clipboard", "type_text":
            return display(args["text"]).map { .text(label: "text", value: $0) } ?? .empty

        case "move_file", "copy_file":
            return transferBody(args, policy: policy)

        default:
            return fieldsBody(args, policy: policy)
        }
    }

    static func writeFileBody(_ args: [String: JSONValue], policy: PathGuard.Policy) -> Body {
        guard let path = display(args["path"]),
              let content = display(args["content"])
        else { return fieldsBody(args, policy: policy) }
        return .fileEdit(
            path: PathGuard.displayPath(path, policy: policy),
            content: content,
            language: language(forPath: path)
        )
    }

    static func readFileBody(_ args: [String: JSONValue], policy: PathGuard.Policy) -> Body {
        var pairs: [(String, String)] = []
        if let path = display(args["path"]) {
            pairs.append(("path", PathGuard.displayPath(path, policy: policy)))
        }
        if let start = display(args["line_start"]) { pairs.append(("line_start", start)) }
        if let end = display(args["line_end"]) { pairs.append(("line_end", end)) }
        return pairs.isEmpty ? .empty : .fields(pairs)
    }

    static func shellBody(_ args: [String: JSONValue], policy: PathGuard.Policy) -> Body {
        guard let cmd = display(args["command"]) else { return .empty }
        var parts = [("command", cmd)]
        if let cwd = display(args["working_directory"]) {
            parts.append(("working_directory", PathGuard.displayPath(cwd, policy: policy)))
        }
        if let timeout = display(args["timeout_seconds"]) {
            parts.append(("timeout_seconds", timeout))
        }
        return parts.count == 1 ? .text(label: "command", value: cmd) : .fields(parts)
    }

    static func transferBody(_ args: [String: JSONValue], policy: PathGuard.Policy) -> Body {
        var pairs: [(String, String)] = []
        if let source = display(args["source"]) {
            pairs.append(("source", PathGuard.displayPath(source, policy: policy)))
        }
        if let dest = display(args["destination"]) {
            pairs.append(("destination", PathGuard.displayPath(dest, policy: policy)))
        }
        return pairs.isEmpty ? .empty : .fields(pairs)
    }

    static func fieldsBody(
        _ args: [String: JSONValue],
        policy: PathGuard.Policy
    ) -> Body {
        let pathKeys: Set<String> = [
            "path", "source", "destination", "working_directory", "script_path",
        ]
        let pairs = args.keys.sorted().compactMap { key -> (String, String)? in
            guard let value = display(args[key]), !value.isEmpty else { return nil }
            let shown = pathKeys.contains(key)
                ? PathGuard.displayPath(value, policy: policy)
                : value
            // Avoid dumping enormous blobs in the generic view.
            let clipped = shown.count > 4_000 ? String(shown.prefix(4_000)) + "\n…" : shown
            return (key, clipped)
        }
        return pairs.isEmpty ? .empty : .fields(pairs)
    }

    // MARK: - Helpers

    static let languageByExtension: [String: String] = [
        "swift": "swift",
        "py": "python",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "tsx": "tsx",
        "jsx": "javascript",
        "css": "css",
        "html": "html",
        "htm": "html",
        "json": "json",
        "md": "markdown",
        "markdown": "markdown",
        "sh": "bash",
        "zsh": "bash",
        "bash": "bash",
        "rs": "rust",
        "go": "go",
        "rb": "ruby",
        "java": "java",
        "kt": "kotlin",
        "c": "c",
        "h": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "cxx": "cpp",
        "hpp": "cpp",
        "yml": "yaml",
        "yaml": "yaml",
        "toml": "toml",
        "sql": "sql",
    ]

    static func language(forPath path: String) -> String? {
        languageByExtension[(path as NSString).pathExtension.lowercased()]
    }

    static func fencedMarkdown(content: String, language: String?) -> String {
        let lang = language ?? ""
        // Use a fence longer than any run inside content to avoid early close.
        var fence = "```"
        while content.contains(fence) { fence += "`" }
        return "\(fence)\(lang)\n\(content)\n\(fence)"
    }

    /// Extracts a string value for a given key from tool arguments JSON.
    static func extractArg(_ json: String, key: String) -> String? {
        let args = decodeArgs(json)
        return display(args[key])
    }

    static func decodeArgs(_ json: String) -> [String: JSONValue] {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = value
        else {
            return [:]
        }
        return object
    }

    static func display(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let string):
            return string

        case .number(let number):
            if number.rounded() == number, number >= Double(Int.min), number <= Double(Int.max) {
                return String(Int(number))
            }
            return String(number)

        case .bool(let flag):
            return flag ? "true" : "false"

        case .null:
            return nil

        case .object, .array:
            guard let data = try? JSONEncoder().encode(value),
                  let encoded = String(data: data, encoding: .utf8)
            else { return nil }
            return encoded
        }
    }

    static func shortPath(
        _ path: String?,
        policy: PathGuard.Policy = .home
    ) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return PathGuard.displayPath(path, policy: policy)
    }
}
