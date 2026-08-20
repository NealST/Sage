//
//  ToolCallPresentation.swift
//  Sage
//

import Foundation

/// Shared parsing + titles for tool-call UI (transcript pills and plan steps).
nonisolated enum ToolCallPresentation {
    enum Body: Equatable {
        /// Full-file write / create preview.
        case fileEdit(path: String, content: String, language: String?)
        /// Single primary text field (shell, clipboard, typed text, …).
        case text(label: String, value: String)
        /// Key/value pairs for smaller args.
        case fields([(key: String, value: String)])
        case empty

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.fileEdit(p1, c1, l1), .fileEdit(p2, c2, l2)):
                return p1 == p2 && c1 == c2 && l1 == l2

            case let (.text(a1, v1), .text(a2, v2)):
                return a1 == a2 && v1 == v2

            case let (.fields(f1), .fields(f2)):
                return f1.map(\.key) == f2.map(\.key) && f1.map(\.value) == f2.map(\.value)

            case (.empty, .empty):
                return true

            default:
                return false
            }
        }
    }

    struct Model: Equatable {
        var title: String
        var body: Body

        var isExpandable: Bool {
            switch body {
            case .empty: return false
            case .fileEdit, .text, .fields: return true
            }
        }
    }

    static func model(
        name: String,
        argumentsJSON: String,
        titleOverride: String? = nil,
        policy: PathGuard.Policy = .home
    ) -> Model {
        let args = decodeArgs(argumentsJSON)
        let title = titleOverride?.nilIfEmpty
            ?? humanTitle(name: name, args: args, policy: policy)
        return Model(title: title, body: body(name: name, args: args, policy: policy))
    }

    static func humanTitle(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy = .home
    ) -> String {
        humanTitle(name: name, args: decodeArgs(argumentsJSON), policy: policy)
    }

    // MARK: - Title

    static func humanTitle(
        name: String,
        args: [String: JSONValue],
        policy: PathGuard.Policy = .home
    ) -> String {
        switch name {
        case "list_directory":
            return "List \(shortPath(display(args["path"]), policy: policy) ?? "folder")"

        case "move_file":
            return "Move \(shortPath(display(args["source"]), policy: policy) ?? "file")"

        case "rename_file":
            return "Rename to \(display(args["new_name"]) ?? "…")"

        case "create_directory":
            return "Create \(shortPath(display(args["path"]), policy: policy) ?? "folder")"

        case "search_files":
            return "Search \(shortPath(display(args["path"]), policy: policy) ?? "files")"

        case "read_text_file":
            return "Read \(shortPath(display(args["path"]), policy: policy) ?? "file")"

        case "write_text_file":
            return "Write \(shortPath(display(args["path"]), policy: policy) ?? "file")"

        case "copy_file":
            return "Copy \(shortPath(display(args["source"]), policy: policy) ?? "file")"

        case "delete_file":
            return "Delete \(shortPath(display(args["path"]), policy: policy) ?? "file")"

        case "run_shell_command":
            let cmd = display(args["command"]) ?? "command"
            let short = cmd.count > 30 ? String(cmd.prefix(27)) + "…" : cmd
            return "Run: \(short)"

        case "get_clipboard":
            return "Read clipboard"

        case "set_clipboard":
            return "Update clipboard"

        case "get_selected_text":
            return "Get selection"

        case "type_text":
            let text = display(args["text"]) ?? ""
            let preview = text.count > 20 ? String(text.prefix(17)) + "…" : text
            return preview.isEmpty ? "Type text" : "Type: \(preview)"

        case "get_screen_info":
            return "Get screen info"

        case "get_frontmost_app":
            return "Check active app"

        case "open_application":
            return "Open \(display(args["name"]) ?? "app")"

        case "open_url":
            return "Open URL"

        case "notify":
            return "Notify: \(display(args["title"]) ?? "…")"

        case "get_system_volume":
            return "Get volume"

        case "set_system_volume":
            return "Set volume to \(display(args["volume"]) ?? "…")%"

        case "toggle_appearance":
            return "Toggle appearance"

        case "create_reminder":
            let title = display(args["title"]) ?? "reminder"
            let short = title.count > 20 ? String(title.prefix(17)) + "…" : title
            return "Remind: \(short)"

        case "take_screenshot":
            return "Take screenshot"

        case "load_skill":
            return "Load skill: \(display(args["name"]) ?? "…")"

        case "load_skill_resource":
            let skill = display(args["skill_name"]) ?? ""
            let path = display(args["path"]) ?? "resource"
            return skill.isEmpty ? "Load resource: \(path)" : "[\(skill)] \(path)"

        case "run_skill_script":
            let script = display(args["script_path"]) ?? "script"
            return "Run: \(script)"

        case "save_skill":
            let action = display(args["action"]) ?? "save"
            let name = display(args["name"]) ?? "skill"
            return action == "enhance" ? "Enhance skill: \(name)" : "Save skill: \(name)"

        case "recall_task_transcript":
            return "Recall earlier turns"

        case "manage_todo_list":
            return "Update todo list"

        default:
            if name.hasPrefix("mcp__") {
                return name.split(separator: "__").last.map(String.init)?
                    .replacingOccurrences(of: "_", with: " ") ?? name
            }
            return name.replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: - Body

    private static func body(
        name: String,
        args: [String: JSONValue],
        policy: PathGuard.Policy
    ) -> Body {
        switch name {
        case "write_text_file":
            guard let path = display(args["path"]),
                  let content = display(args["content"])
            else { return fieldsBody(args, policy: policy) }
            let shown = PathGuard.displayPath(path, policy: policy)
            return .fileEdit(path: shown, content: content, language: language(forPath: path))

        case "read_text_file":
            var pairs: [(String, String)] = []
            if let path = display(args["path"]) {
                pairs.append(("path", PathGuard.displayPath(path, policy: policy)))
            }
            if let start = display(args["line_start"]) { pairs.append(("line_start", start)) }
            if let end = display(args["line_end"]) { pairs.append(("line_end", end)) }
            return pairs.isEmpty ? .empty : .fields(pairs)

        case "run_shell_command":
            if let cmd = display(args["command"]) {
                var parts = [("command", cmd)]
                if let cwd = display(args["working_directory"]) {
                    parts.append(("working_directory", PathGuard.displayPath(cwd, policy: policy)))
                }
                if let timeout = display(args["timeout_seconds"]) {
                    parts.append(("timeout_seconds", timeout))
                }
                return parts.count == 1 ? .text(label: "command", value: cmd) : .fields(parts)
            }
            return .empty

        case "set_clipboard", "type_text":
            if let text = display(args["text"]) {
                return .text(label: "text", value: text)
            }
            return .empty

        case "move_file", "copy_file":
            var pairs: [(String, String)] = []
            if let source = display(args["source"]) {
                pairs.append(("source", PathGuard.displayPath(source, policy: policy)))
            }
            if let dest = display(args["destination"]) {
                pairs.append(("destination", PathGuard.displayPath(dest, policy: policy)))
            }
            return pairs.isEmpty ? .empty : .fields(pairs)

        default:
            return fieldsBody(args, policy: policy)
        }
    }

    private static func fieldsBody(
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

    static func language(forPath path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "mjs", "cjs": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "tsx"
        case "jsx": return "javascript"
        case "css": return "css"
        case "html", "htm": return "html"
        case "json": return "json"
        case "md", "markdown": return "markdown"
        case "sh", "zsh", "bash": return "bash"
        case "rs": return "rust"
        case "go": return "go"
        case "rb": return "ruby"
        case "java": return "java"
        case "kt": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "yml", "yaml": return "yaml"
        case "toml": return "toml"
        case "sql": return "sql"
        default: return nil
        }
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

    private static func decodeArgs(_ json: String) -> [String: JSONValue] {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = value
        else {
            return [:]
        }
        return object
    }

    private static func display(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let s):
            return s

        case .number(let n):
            if n.rounded() == n, n >= Double(Int.min), n <= Double(Int.max) {
                return String(Int(n))
            }
            return String(n)

        case .bool(let b):
            return b ? "true" : "false"

        case .null:
            return nil

        case .object, .array:
            guard let data = try? JSONEncoder().encode(value),
                  let s = String(data: data, encoding: .utf8)
            else { return nil }
            return s
        }
    }

    private static func shortPath(
        _ path: String?,
        policy: PathGuard.Policy = .home
    ) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return PathGuard.displayPath(path, policy: policy)
    }
}
