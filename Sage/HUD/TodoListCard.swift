//
//  TodoListCard.swift
//  Sage
//

import SwiftUI

struct TodoListCard: View {
    let items: [AgentTodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Todos")
                .font(.system(size: SageDesign.Typography.captionSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: SageDesign.Spacing.small) {
                    Image(systemName: icon(for: item.status))
                        .font(.system(size: SageDesign.Typography.captionSize, weight: .semibold))
                        .foregroundStyle(color(for: item.status))
                        .frame(width: 12)
                    Text(item.title)
                        .font(.system(size: SageDesign.Typography.captionSize))
                        .foregroundStyle(item.status == .completed ? .secondary : .primary)
                        .strikethrough(item.status == .completed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel("\(item.title), \(label(for: item.status))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Todo list")
    }

    private func icon(for status: AgentTodoItem.Status) -> String {
        switch status {
        case .notStarted: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private func color(for status: AgentTodoItem.Status) -> Color {
        switch status {
        case .notStarted: return .secondary
        case .inProgress: return .accentColor
        case .completed: return .secondary
        }
    }

    private func label(for status: AgentTodoItem.Status) -> String {
        switch status {
        case .notStarted: return "not started"
        case .inProgress: return "in progress"
        case .completed: return "completed"
        }
    }
}
