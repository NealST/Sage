//
//  TaskHistoryBrowserView.swift
//  Sage
//
//  Browsable task history for one session scope: search, switch, delete.
//  Data is TaskSummary metadata only — full tasks load on activation.
//

import SwiftUI

struct TaskHistoryBrowserView: View {
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type
    /// Sheet contexts have no toolbar — the inline field renders everywhere.
    @State var showsInlineSearch = true

    @State private var summaries: [TaskSummary] = []
    @State private var searchText = ""
    @State private var deleteTarget: TaskSummary?
    @State private var isDeleting = false
    @State private var loadFailed = false

    private let repository: any TaskRepository
    private let projectID: UUID?

    init(repository: any TaskRepository, projectID: UUID?) {
        self.repository = repository
        self.projectID = projectID
    }

    private var filtered: [TaskSummary] {
        let base = summaries.filter { !$0.isScheduled }
        guard !searchText.isEmpty else { return base }
        let query = searchText.lowercased()
        return base.filter { summary in
            summary.displayTitle?.lowercased().contains(query) == true
                || summary.summary?.lowercased().contains(query) == true
        }
    }

    var body: some View {
        Group {
            if loadFailed {
                ContentUnavailableView(
                    "Couldn’t load tasks",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The local database could not be read.")
                )
            } else if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { row(for: $0) }
                }
                .listStyle(.plain)
                .sageScrollEdgeGlass()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsInlineSearch {
                inlineSearchField
                    .padding(.horizontal, SageDesign.Spacing.large)
                    .padding(.vertical, SageDesign.Spacing.small)
                    .sageGlassToolbar()
            }
        }
        .task(id: projectID) { await reload() }
        .refreshable { await reload() }
        .alert(
            "Delete this task?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("Move to Trash", role: .destructive) {
                if let target = deleteTarget {
                    Task { await deleteTask(target) }
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            if let title = deleteTarget?.displayTitle {
                Text("“\(title)” will be removed from Sage. A Markdown copy of its transcript is kept in the Trash.")
            } else {
                Text("This task will be removed from Sage. A Markdown copy of its transcript is kept in the Trash.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "No tasks yet" : "No matching tasks",
                systemImage: searchText.isEmpty ? "tray" : "magnifyingglass"
            )
        } description: {
            Text(
                searchText.isEmpty
                    ? "Finished tasks in this scope appear here."
                    : "Try a different search term."
            )
        }
    }

    private var inlineSearchField: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .sageFont(type.caption)
                .foregroundStyle(.tertiary)
            TextField("Search tasks", text: $searchText)
                .sageFont(type.body)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .sageFont(type.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, SageDesign.Spacing.medium)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search tasks")
    }

    private func row(for summary: TaskSummary) -> some View {
        HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
            Image(systemName: statusIcon(summary.status))
                .sageFont(type.caption)
                .foregroundStyle(statusColor(summary.status))
                .frame(width: type.caption + 2)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayTitle ?? "Task")
                    .sageFont(type.body, weight: summary.id == activeID ? .semibold : .regular)
                    .lineLimit(2)
                Text(summary.updatedAt.formatted(.relative(presentation: .named)))
                    .sageMicro(type.micro)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if summary.id == activeID {
                Text("Active")
                    .sageMicro(type.micro, weight: .medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
                    )
            } else {
                Menu {
                    Button("Open") { activate(summary) }
                    Button("Rename…") { renameTask(summary) }
                    Button("Export as Markdown…") { exportTask(summary) }
                    Button("Delete…", role: .destructive) { deleteTarget = summary }
                } label: {
                    Image(systemName: "ellipsis")
                        .sageFont(type.caption)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .buttonStyle(.plain)
                .help("Task actions")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { activate(summary) }
        .contextMenu {
            Button("Open") { activate(summary) }
            Button("Rename…") { renameTask(summary) }
            Button("Export as Markdown…") { exportTask(summary) }
            Button("Delete…", role: .destructive) { deleteTarget = summary }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel(summary))
        .accessibilityHint(summary.id == activeID ? "" : "Opens this task")
    }

    private var activeID: UUID? {
        session.agent.state.activeTaskID
    }

    private func reload() async {
        do {
            let snapshot = try await repository.loadScopedWorkspace(projectID: projectID)
            summaries = TaskSummary.sortedForRecents(snapshot.recentSummaries)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func activate(_ summary: TaskSummary) {
        guard summary.id != activeID else { return }
        session.resetComposer()
        Task { await session.agent.activateTask(summary.id) }
    }

    private func exportTask(_ summary: TaskSummary) {
        Task {
            guard let task = try? await repository.loadTask(id: summary.id) else { return }
            TaskMarkdownExporter.exportThroughSavePanel(for: task)
        }
    }

    private func renameTask(_ summary: TaskSummary) {
        guard let name = promptTaskName(current: summary.displayTitle ?? "") else { return }
        let trimmed = String(name.prefix(80))
        Task {
            do {
                // `updateTopic` writes topic + abstract together — preserve the
                // generated abstract so routing/recall behavior is unchanged.
                let existing = try await repository.loadTaskMetadata(id: summary.id)
                try await repository.updateTopic(
                    taskID: summary.id,
                    topic: trimmed,
                    abstract: existing?.abstract ?? "",
                    topicUpdatedAt: .now
                )
                if summary.id == activeID, var active = session.agent.state.activeTask {
                    active.topic = trimmed
                    active.topicUpdatedAt = .now
                    active.updatedAt = .now
                    session.agent.state.activeTask = active
                    session.agent.state.refreshSummary(for: active)
                }
                await reload()
            } catch {
                session.agent.reportFailure(
                    "Could not rename the task: \(error.localizedDescription)"
                )
            }
        }
    }

    @MainActor
    private func promptTaskName(current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename Task"
        alert.informativeText = "This name appears in the task list and window title."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.placeholderString = "Task name"
        nameField.stringValue = current
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func deleteTask(_ summary: TaskSummary) {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await trashTranscriptThenDelete(summary)
                if summary.id == activeID {
                    session.agent.state.removeSummary(id: summary.id)
                    _ = await session.agent.startFresh()
                } else {
                    session.agent.state.removeSummary(id: summary.id)
                }
                await reload()
            } catch {
                session.agent.reportFailure(
                    "Could not delete the task: \(error.localizedDescription)"
                )
            }
        }
    }

    /// The Trash copy is best-effort forgiveness — a failed copy is logged,
    /// not fatal, so deletion behaves the same on a read-only volume.
    private func trashTranscriptThenDelete(_ summary: TaskSummary) async throws {
        if let task = try await repository.loadTask(id: summary.id) {
            do {
                try await Task.detached(priority: .utility) {
                    try TaskMarkdownExporter.writeTrashCopy(of: task)
                }.value
            } catch {
                PersistenceLogger.warn("task_trash_copy_failed id=\(summary.id)", error: error)
            }
        }
        try await repository.deleteTask(id: summary.id)
    }

    private func accessibilityRowLabel(_ summary: TaskSummary) -> String {
        let title = summary.displayTitle ?? "Task"
        if summary.id == activeID { return "\(title), active" }
        return "\(title), \(summary.updatedAt.formatted(.relative(presentation: .named)))"
    }

    private func statusIcon(_ status: TaskStatus) -> String {
        switch status {
        case .active, .awaitingApproval: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .active, .awaitingApproval: return .accentColor
        case .completed: return SageDesign.Palette.success
        case .failed: return SageDesign.Palette.danger
        }
    }
}
