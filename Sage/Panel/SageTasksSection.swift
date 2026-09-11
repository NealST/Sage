//
//  SageTasksSection.swift
//  Sage
//
//  Task-history block on the project History tab — collapsible recent tasks
//  above the git log. Expand for the full searchable browser.
//

import SwiftUI

struct SageTasksSection: View {
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type

    @State private var isExpanded = false
    @State private var isPresentingBrowser = false

    let repository: any TaskRepository
    let projectID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Button {
                withAnimation(SageDesign.Motion.expandAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: SageDesign.Spacing.small) {
                    Image(systemName: "checklist")
                        .sageFont(type.caption)
                        .foregroundStyle(.secondary)
                    Text("Sage Tasks")
                        .sageFont(type.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Text("\(recentUserTasks.count)")
                        .sageMicro(type.micro)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .sageFont(type.icon, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(SageDesign.Motion.expandAnimation, value: isExpanded)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, SageDesign.Spacing.large)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sage tasks, \(recentUserTasks.count) recent")
            .accessibilityHint(isExpanded ? "Collapses the task list" : "Expands the task list")

            if isExpanded {
                if recentUserTasks.isEmpty {
                    Text("Tasks you start with Sage in this project appear here.")
                        .sageMicro(type.micro)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SageDesign.Spacing.large)
                        .padding(.bottom, SageDesign.Spacing.small)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentUserTasks.prefix(8)) { summary in
                            taskRow(summary)
                        }
                    }
                    .padding(.horizontal, SageDesign.Spacing.large)
                    .padding(.bottom, SageDesign.Spacing.small)

                    Button("Browse All Tasks…") {
                        isPresentingBrowser = true
                    }
                    .sageFont(type.caption)
                    .padding(.horizontal, SageDesign.Spacing.large)
                    .padding(.bottom, SageDesign.Spacing.small)
                    .help("Search, open, and delete tasks")
                }
            }
        }
        .sheet(isPresented: $isPresentingBrowser) {
            TaskHistorySheet(repository: repository, projectID: projectID)
        }
    }

    private var recentUserTasks: [TaskSummary] {
        session.agent.state.recentSummaries.filter { !$0.isScheduled }
    }

    private func taskRow(_ summary: TaskSummary) -> some View {
        HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
            Image(systemName: statusIcon(summary.status))
                .sageFont(type.caption)
                .foregroundStyle(statusColor(summary.status))
                .frame(width: type.caption + 2)
                .padding(.top, 2)
            Text(summary.displayTitle ?? "Task")
                .sageFont(type.body, weight: summary.id == activeID ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(summary.updatedAt.formatted(.relative(presentation: .named)))
                .sageMicro(type.micro)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { activate(summary) }
        .contextMenu {
            Button("Open") { activate(summary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(summary.displayTitle ?? "Task"), \(summary.updatedAt.formatted(.relative(presentation: .named)))"
        )
        .accessibilityHint(summary.id == activeID ? "Current task" : "Opens this task")
    }

    private var activeID: UUID? {
        session.agent.state.activeTaskID
    }

    private func activate(_ summary: TaskSummary) {
        guard summary.id != activeID else { return }
        session.resetComposer()
        Task { await session.agent.activateTask(summary.id) }
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

/// Standalone full-browser sheet content (General window / "Browse All").
struct TaskHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sageTypography) private var type

    let repository: any TaskRepository
    let projectID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SageDesign.Spacing.small) {
                Text("Task History")
                    .sageFont(type.title, weight: .semibold)
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .sageFont(type.caption, weight: .semibold)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close task history")
            }
            .padding(.horizontal, SageDesign.Spacing.large)
            .padding(.top, SageDesign.Spacing.medium)
            .padding(.bottom, SageDesign.Spacing.small)

            TaskHistoryBrowserView(repository: repository, projectID: projectID)
        }
        .frame(minWidth: 460, minHeight: 420)
        .sageScaledTypography()
        .sageAccessibilityObservation()
    }
}
