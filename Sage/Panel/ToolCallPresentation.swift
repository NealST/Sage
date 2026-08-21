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
            case let (
                .fileEdit(leftPath, leftContent, leftLanguage),
                .fileEdit(rightPath, rightContent, rightLanguage)
            ):
                return leftPath == rightPath
                    && leftContent == rightContent
                    && leftLanguage == rightLanguage

            case let (.text(leftLabel, leftValue), .text(rightLabel, rightValue)):
                return leftLabel == rightLabel && leftValue == rightValue

            case let (.fields(leftFields), .fields(rightFields)):
                return leftFields.map(\.key) == rightFields.map(\.key)
                    && leftFields.map(\.value) == rightFields.map(\.value)

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
        if let title = fileToolTitle(name: name, args: args, policy: policy) {
            return title
        }
        if let title = systemToolTitle(name: name, args: args) {
            return title
        }
        if let title = skillToolTitle(name: name, args: args) {
            return title
        }
        if name.hasPrefix("mcp__") {
            let lastSegment = name.split(separator: "__").last.map(String.init)
            return lastSegment?.replacingOccurrences(of: "_", with: " ") ?? name
        }
        return name.replacingOccurrences(of: "_", with: " ")
    }

    static func fileToolTitle(
        name: String,
        args: [String: JSONValue],
        policy: PathGuard.Policy
    ) -> String? {
        if name == "run_shell_command" {
            let cmd = display(args["command"]) ?? "command"
            let short = cmd.count > 30 ? String(cmd.prefix(27)) + "…" : cmd
            return "Run: \(short)"
        }
        if name == "rename_file" {
            return "Rename to \(display(args["new_name"]) ?? "…")"
        }
        guard let verb = fileToolVerbs[name] else { return nil }
        let pathKey = (name == "move_file" || name == "copy_file") ? "source" : "path"
        let fallback: String
        if name == "search_files" {
            fallback = "files"
        } else if name == "list_directory" || name == "create_directory" {
            fallback = "folder"
        } else {
            fallback = "file"
        }
        let target = shortPath(display(args[pathKey]), policy: policy) ?? fallback
        return "\(verb) \(target)"
    }

    static let fileToolVerbs: [String: String] = [
        "list_directory": "List",
        "move_file": "Move",
        "create_directory": "Create",
        "search_files": "Search",
        "read_text_file": "Read",
        "write_text_file": "Write",
        "copy_file": "Copy",
        "delete_file": "Delete",
    ]

    static let staticSystemTitles: [String: String] = [
        "get_clipboard": "Read clipboard",
        "set_clipboard": "Update clipboard",
        "get_selected_text": "Get selection",
        "get_screen_info": "Get screen info",
        "get_frontmost_app": "Check active app",
        "open_url": "Open URL",
        "get_system_volume": "Get volume",
        "toggle_appearance": "Toggle appearance",
        "take_screenshot": "Take screenshot",
    ]

    static func systemToolTitle(name: String, args: [String: JSONValue]) -> String? {
        if let title = staticSystemTitles[name] {
            return title
        }
        switch name {
        case "type_text":
            let text = display(args["text"]) ?? ""
            let preview = text.count > 20 ? String(text.prefix(17)) + "…" : text
            return preview.isEmpty ? "Type text" : "Type: \(preview)"

        case "open_application":
            return "Open \(display(args["name"]) ?? "app")"

        case "notify":
            return "Notify: \(display(args["title"]) ?? "…")"

        case "set_system_volume":
            return "Set volume to \(display(args["volume"]) ?? "…")%"

        case "create_reminder":
            let title = display(args["title"]) ?? "reminder"
            let short = title.count > 20 ? String(title.prefix(17)) + "…" : title
            return "Remind: \(short)"

        default:
            return nil
        }
    }

    static func skillToolTitle(name: String, args: [String: JSONValue]) -> String? {
        switch name {
        case "load_skill":
            return "Load skill: \(display(args["name"]) ?? "…")"

        case "load_skill_resource":
            let skill = display(args["skill_name"]) ?? ""
            let path = display(args["path"]) ?? "resource"
            return skill.isEmpty ? "Load resource: \(path)" : "[\(skill)] \(path)"

        case "run_skill_script":
            return "Run: \(display(args["script_path"]) ?? "script")"

        case "save_skill":
            let action = display(args["action"]) ?? "save"
            let skillName = display(args["name"]) ?? "skill"
            return action == "enhance" ? "Enhance skill: \(skillName)" : "Save skill: \(skillName)"

        case "recall_task_transcript":
            return "Recall earlier turns"

        case "manage_todo_list":
            return "Update todo list"

        default:
            return nil
        }
    }

    // MARK: - Body

}
