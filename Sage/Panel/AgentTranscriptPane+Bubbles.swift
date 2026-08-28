//
//  AgentTranscriptPane+Bubbles.swift
//  Sage
//

import SwiftUI

extension AgentTranscriptPane {
    @ViewBuilder
    func phaseAccessory(onStreamScroll: @escaping () -> Void) -> some View {
        switch session.agent.state.phase {
        case .thinking:
            thinkingAccessory(onStreamScroll: onStreamScroll)

        case .awaitingConfirmation, .executing:
            confirmationAccessory()

        case .failed(let message):
            failureAccessory(message)

        case .idle, .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    func thinkingAccessory(onStreamScroll: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
            todoListIfPresent
            ThinkingStreamAccessory(
                retryState: session.agent.state.retryState,
                canStop: session.agent.canStop,
                onStop: { session.agent.stop() },
                onStreamScroll: onStreamScroll
            )
        }
    }

    @ViewBuilder
    func confirmationAccessory() -> some View {
        let isExecuting: Bool = {
            if case .executing = session.agent.state.phase { return true }
            return false
        }()
        VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
            todoListIfPresent
            confirmationChrome(isExecuting: isExecuting)
        }
    }

    @ViewBuilder var todoListIfPresent: some View {
        if let todos = session.agent.state.activeTask?.todos, !todos.isEmpty {
            TodoListCard(items: todos)
        }
    }

    @ViewBuilder
    func confirmationChrome(isExecuting: Bool) -> some View {
        switch session.agent.turnChrome {
        case .workPlan:
            if let workPlan = session.agent.state.activeTask?.workPlan {
                WorkPlanCard(
                    plan: workPlan,
                    isExecuting: isExecuting,
                    onConfirm: { Task { await session.agent.confirmWorkPlan() } },
                    onCancel: { Task { await session.agent.cancelPendingPlan() } },
                    onStop: { session.agent.stop() }
                )
            }

        case .toolBatch:
            if let plan = session.agent.planProgress.plan
                ?? session.agent.state.activeTask?.pendingPlan {
                PlanCardView(
                    plan: plan,
                    isExecuting: isExecuting,
                    onConfirm: { Task { await session.agent.confirmToolBatch() } },
                    onCancel: { Task { await session.agent.cancelPendingPlan() } },
                    onStop: { session.agent.stop() }
                )
            }

        case .toolRoundLimit:
            if case .toolRoundLimit(let current, let next) = session.agent.state.pendingPrompt {
                ToolRoundLimitCard(
                    currentLimit: current,
                    nextLimit: next,
                    onContinue: { Task { await session.agent.confirmToolRoundLimit() } },
                    onFinish: { Task { await session.agent.finishToolRoundLimit() } }
                )
            }

        case .toolApproval:
            if case .toolApproval(_, let name, let args, let title) = session.agent.state.pendingPrompt {
                ToolApprovalCard(
                    title: title,
                    toolName: name,
                    argumentsJSON: args,
                    onAllowOnce: { Task { await session.agent.confirmToolApproval(scope: .once) } },
                    onAllowSession: { Task { await session.agent.confirmToolApproval(scope: .task) } },
                    onAllowTool: { Task { await session.agent.confirmToolApproval(scope: .always) } },
                    onSkip: { Task { await session.agent.skipToolApproval() } }
                )
            }

        case .none:
            EmptyView()
        }
    }

    func failureAccessory(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: SageDesign.Typography.bodySize))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.small) {
                if session.agent.canRetryFailure {
                    Button("Retry") {
                        stickToBottom = true
                        Task { await session.agent.retryLastFailure() }
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.agent.state.isBusy)
                }
                if looksLikeConfigurationError(message) {
                    Button("Open Settings") {
                        NotificationCenter.default.post(name: .sageOpenSettings, object: nil)
                    }
                    .controlSize(.small)
                }
                Button("Dismiss") {
                    Task { await session.agent.dismissFailure() }
                }
                .controlSize(.small)
                .help(
                    session.agent.state.hasPendingPlan
                        ? "Abandon the pending plan"
                        : "Dismiss this error"
                )
            }
        }
    }

    @ViewBuilder
    func eventBubble(_ event: AgentEvent, toolIndex: ToolResultIndex) -> some View {
        switch event.kind {
        case .userInput:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                if !event.attachments.isEmpty {
                    AttachmentChipBar(
                        attachments: event.attachments,
                        selectedID: nil,
                        showsRemove: false
                    )
                }
                if !event.content.isEmpty {
                    Text(event.content)
                        .font(.system(size: SageDesign.Typography.inputSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

        case .assistantResponse:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                if !event.content.isEmpty {
                    MarkdownContentView(markdown: event.content, collapsible: true)
                }
                if let calls = event.toolCalls, !calls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calls, id: \.id) { call in
                            ToolCallView(
                                name: call.name,
                                argumentsJSON: call.argumentsJSON,
                                titleOverride: Self.loadedSkillTitle(for: call),
                                resultContent: toolIndex.successContent(for: call.id),
                                previewAgainstDisk: toolIndex.shouldPreviewAgainstDisk(callID: call.id)
                            )
                        }
                    }
                }
            }

        case .toolResult:
            ToolResultView(content: event.content)

        case .systemInstruction:
            EmptyView()
        }
    }

    func looksLikeConfigurationError(_ message: String) -> Bool {
        AppState.looksLikeConfigurationError(message, isConfigured: appState.settings.isConfigured)
    }

    func scrollToLatest(using proxy: ScrollViewProxy) {
        if let animation = SageDesign.Motion.scrollAnimation {
            withAnimation(animation) {
                proxy.scrollTo("phase-accessory", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("phase-accessory", anchor: .bottom)
        }
    }

    func scrollToLatestStreaming(using proxy: ScrollViewProxy) {
        let animation = AccessibilitySettings.shared.reduceMotion
            ? nil : SageDesign.Motion.streamingScroll
        if let animation {
            withAnimation(animation) {
                proxy.scrollTo("phase-accessory", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("phase-accessory", anchor: .bottom)
        }
    }

    /// Slash / explicit `load_skill` events (legacy `auto_skill_` ids still match).
    static func isSyntheticSkillLoad(_ callID: String) -> Bool {
        callID.hasPrefix("skill_load_") || callID.hasPrefix("auto_skill_")
    }

    static func loadedSkillTitle(for call: ToolCallRecord) -> String? {
        guard isSyntheticSkillLoad(call.id) else { return nil }
        let name = ToolCallPresentation.extractArg(call.argumentsJSON, key: "name") ?? "…"
        return "Loaded skill: \(name)"
    }
}
