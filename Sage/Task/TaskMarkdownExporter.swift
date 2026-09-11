//
//  TaskMarkdownExporter.swift
//  Sage
//
//  Renders a task transcript to Markdown. Powers the Trash copy written
//  when deleting a task and the user-facing Export command.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated enum TaskMarkdownExporter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func title(for task: TaskRecord) -> String {
        TopicDriftDetector.threadLabel(
            topic: task.topic,
            abstract: task.abstract,
            summary: task.summary
        ) ?? "Untitled Task"
    }

    /// Full transcript render: user and assistant turns in order, with tool
    /// activity summarized so the file stays readable.
    static func markdown(for task: TaskRecord, exportedAt: Date = .now) -> String {
        var toolNames: [String: String] = [:]
        for event in task.events {
            for call in event.toolCalls ?? [] {
                toolNames[call.id] = call.name
            }
        }

        var lines: [String] = []
        lines.append("# \(title(for: task))")
        lines.append("")
        lines.append(
            "Exported from Sage on \(exportedAt.formatted(date: .abbreviated, time: .shortened))"
        )
        lines.append("")
        lines.append("---")
        lines.append("")

        for event in task.events where event.kind != .systemInstruction {
            switch event.kind {
            case .userInput:
                lines.append("## You — \(timeFormatter.string(from: event.createdAt))")
                lines.append("")
                if !event.attachments.isEmpty {
                    let names = event.attachments.map(\.displayName).joined(separator: ", ")
                    lines.append("*Attachments: \(names)*")
                    lines.append("")
                }
                appendBody(event.content, to: &lines)

            case .assistantResponse:
                if !event.content.isEmpty {
                    lines.append("## Sage — \(timeFormatter.string(from: event.createdAt))")
                    lines.append("")
                    appendBody(event.content, to: &lines)
                }
                if let calls = event.toolCalls, !calls.isEmpty {
                    lines.append("**Tools:** \(calls.map(\.name).joined(separator: ", "))")
                    lines.append("")
                }

            case .toolResult:
                let name = toolNames[event.toolCallID ?? ""] ?? "tool"
                let excerpt = excerpt(of: event.content)
                lines.append("> \(timeFormatter.string(from: event.createdAt)) · \(name) — \(excerpt)")
                lines.append("")

            case .systemInstruction:
                continue
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Filesystem-safe file name for an export, disambiguated by date.
    static func suggestedFileName(for task: TaskRecord, exportedAt: Date = .now) -> String {
        let title = sanitized(title(for: task))
        let stamp = stampFormatter.string(from: exportedAt)
        return "Sage Task — \(title) (\(stamp)).md"
    }

    /// Writes the transcript to a staging file, then moves that file into the
    /// user's Trash. Throwing means the Trash copy was not created; callers
    /// decide whether that blocks deletion.
    static func writeTrashCopy(of task: TaskRecord, exportedAt: Date = .now) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedFileName(for: task, exportedAt: exportedAt))
        guard let data = markdown(for: task, exportedAt: exportedAt).data(using: .utf8) else { return }
        try data.write(to: staging, options: .atomic)
        try FileManager.default.trashItem(at: staging, resultingItemURL: nil)
    }

    /// Save-panel flow for the user-facing Export command.
    @MainActor
    static func exportThroughSavePanel(for task: TaskRecord) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = suggestedFileName(for: task)
        panel.title = "Export Task"
        panel.message = "Exports the task transcript as Markdown."
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown(for: task).data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t export the task"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func appendBody(_ content: String, to lines: inout [String]) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append(trimmed)
            lines.append("")
        }
    }

    /// First line of a tool result, capped so a huge payload can't bloat the export.
    private static func excerpt(of content: String) -> String {
        let firstLine = content
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard firstLine.count > 200 else { return firstLine.isEmpty ? "(no output)" : firstLine }
        return String(firstLine.prefix(197)) + "…"
    }

    private static func sanitized(_ text: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = text
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Task" : String(cleaned.prefix(80))
    }
}
