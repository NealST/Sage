//
//  TodoListCard.swift
//  Sage
//

import SwiftUI

/// One row's home geometry inside the card — frozen at drag start so target
/// math never reads mid-flight (shifted) positions.
private struct TodoRowFrame: Equatable {
    var midY: CGFloat
    var height: CGFloat
}

private struct TodoRowFramesKey: PreferenceKey {
    static var defaultValue: [Int: TodoRowFrame] = [:]

    static func reduce(
        value: inout [Int: TodoRowFrame],
        nextValue: () -> [Int: TodoRowFrame]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TodoListCard: View {
    @Environment(\.sageTypography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [AgentTodoItem]
    /// Reordering is user-only while no turn is in flight — the agent rewrites
    /// todos as it works, and a mid-turn reorder would be clobbered anyway.
    var canReorder: Bool = false
    var onReorder: (([AgentTodoItem]) -> Void)?

    @State private var draggedIndex: Int?
    @State private var dragOffset: CGFloat = 0
    /// Insertion index for the dragged row (array semantics without the item).
    @State private var dropTargetIndex: Int?
    @State private var rowFrames: [Int: TodoRowFrame] = [:]

    private static let cardSpace = "todoCardSpace"

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
            HStack(spacing: SageDesign.Spacing.extraSmall) {
                Text("Todos")
                    .sageFont(type.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text("\(completedCount) of \(items.count)")
                        .sageFont(type.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if canReorder, onReorder != nil {
                    Spacer(minLength: 0)
                    Image(systemName: "line.3.horizontal")
                        .sageFont(type.icon)
                        .foregroundStyle(.tertiary)
                        .opacity(0.6)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
            }
        }
        .coordinateSpace(name: Self.cardSpace)
        .onPreferenceChange(TodoRowFramesKey.self) { frames in
            // Freeze during a drag — target math must read home positions.
            if draggedIndex == nil {
                rowFrames = frames
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Todo list, \(completedCount) of \(items.count) completed")
    }

    private func row(_ item: AgentTodoItem, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SageDesign.Spacing.small) {
            Image(systemName: icon(for: item.status))
                .sageFont(type.caption, weight: .semibold)
                .foregroundStyle(color(for: item.status))
                .frame(width: type.caption + 2)
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating,
                    isActive: !reduceMotion && item.status == .inProgress
                )
                .sageSymbolEffect(.bounce, value: item.status == .completed)
            Text(item.title)
                .sageFont(type.caption)
                .foregroundStyle(item.status == .completed ? .secondary : .primary)
                .strikethrough(item.status == .completed)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TodoRowFramesKey.self,
                    value: [
                        index: TodoRowFrame(
                            midY: geo.frame(in: .named(Self.cardSpace)).midY,
                            height: geo.frame(in: .named(Self.cardSpace)).height
                        )
                    ]
                )
            }
        )
        .offset(y: rowDisplayOffset(for: index))
        .scaleEffect(draggedIndex == index ? 1.02 : 1)
        .opacity(draggedIndex == index ? 0.9 : 1)
        .zIndex(draggedIndex == index ? 1 : 0)
        .animation(SageDesign.Motion.dragSettle, value: draggedIndex)
        .gesture(reorderGesture(index: index))
        .accessibilityLabel("\(item.title), \(label(for: item.status))")
        .accessibilityHint(canReorder && onReorder != nil ? "Drag vertically to reorder" : "")
    }

    /// Drag a row to reorder — tracks 1:1, commits on release. Vertical intent
    /// only: horizontal movement belongs to nothing here, but the guard keeps
    /// the gesture honest if the card ever nests in a horizontal scroller.
    private func reorderGesture(index: Int) -> _EndedGesture<_ChangedGesture<DragGesture>>? {
        guard canReorder, onReorder != nil else { return nil }
        return DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                if draggedIndex == nil {
                    draggedIndex = index
                    dropTargetIndex = index
                }
                guard draggedIndex == index else { return }
                dragOffset = value.translation.height
                updateDropTarget()
            }
            .onEnded { value in
                guard let dragged = draggedIndex, dragged == index else { return }
                let target = dropTargetIndex ?? dragged
                var reordered = items
                if target != dragged {
                    let moved = reordered.remove(at: dragged)
                    reordered.insert(moved, at: target)
                }
                let settle = SageDesign.Motion.dragSettle(
                    velocity: value.velocity.height,
                    from: dragOffset
                )
                withAnimation(settle) {
                    dragOffset = 0
                    draggedIndex = nil
                    dropTargetIndex = nil
                }
                if target != dragged {
                    onReorder?(reordered)
                }
            }
    }

    private func updateDropTarget() {
        guard let dragged = draggedIndex,
              let draggedMid = rowFrames[dragged]?.midY else { return }
        let projected = draggedMid + dragOffset
        var target = 0
        for (index, frame) in rowFrames where index != dragged {
            if frame.midY < projected { target += 1 }
        }
        if target != dropTargetIndex {
            withAnimation(SageDesign.Motion.dragSettle) {
                dropTargetIndex = target
            }
        }
    }

    /// The dragged row follows the pointer 1:1; neighbors slide out of the way
    /// by exactly one dragged-row height (make-room preview, like
    /// NSCollectionView placeholders). Final layout is exact on commit.
    private func rowDisplayOffset(for index: Int) -> CGFloat {
        guard let dragged = draggedIndex, let target = dropTargetIndex else { return 0 }
        if index == dragged { return dragOffset }
        let draggedHeight = rowFrames[dragged]?.height ?? 0
        if dragged < index, index <= target { return -draggedHeight }
        if target <= index, index < dragged { return draggedHeight }
        return 0
    }

    private var completedCount: Int {
        items.filter { $0.status == .completed }.count
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
        // Green = completion, matching stepSuccess in the transcript.
        case .completed: return SageDesign.Palette.success
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
