//
//  AgentTranscriptPane+Bubbles.swift
//  Sage
//

import SwiftUI

extension AgentTranscriptPane {
    /// One glass cluster across phases: the todo list keeps its identity when
    /// the phase flips, and the plan skeleton can morph into the confirmed
    /// plan card (matched glass) instead of cross-fading.
    @ViewBuilder
    func phaseAccessory(onStreamScroll: @escaping () -> Void) -> some View {
        GlassEffectContainer(spacing: SageDesign.Glass.containerSpacing) {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                todoListIfPresent
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
        }
    }

    @ViewBuilder
    func thinkingAccessory(onStreamScroll: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
            if case .reviewMustFix(_, let message) = session.agent.state.pendingPrompt {
                ReviewFindingsCard(message: message, mode: .continuing)
            }
            ThinkingStreamAccessory(
                retryState: session.agent.state.retryState,
                onStreamScroll: onStreamScroll,
                status: session.agent.state.isReviewing ? "Checking the project…" : nil,
                planGlassNamespace: planGlassNamespace,
                agentCanStop: session.agent.canStop,
                onAgentStop: { session.agent.stop() },
                onRetryNow: { session.agent.retryNow() }
            )
        }
    }

    @ViewBuilder
    func confirmationAccessory() -> some View {
        let isExecuting: Bool = {
            if case .executing = session.agent.state.phase { return true }
            return false
        }()
        let freezeConfirmationActions = session.agent.state.shouldDisableConfirmationActions
        let bindsReturnShortcut = !composerFocused && !freezeConfirmationActions
        confirmationChrome(
            isExecuting: isExecuting,
            bindsReturnShortcut: bindsReturnShortcut
        )
        .disabled(freezeConfirmationActions)
        .opacity(freezeConfirmationActions ? 0.55 : 1)
    }

    @ViewBuilder var todoListIfPresent: some View {
        if let todos = session.agent.state.activeTask?.todos, !todos.isEmpty {
            TodoListCard(
                items: todos,
                canReorder: !session.agent.state.isBusy,
                onReorder: { reordered in
                    Task { await session.agent.reorderTodos(reordered) }
                }
            )
        }
    }

    @ViewBuilder
    func confirmationChrome(isExecuting: Bool, bindsReturnShortcut: Bool) -> some View {
        switch session.agent.turnChrome {
        case .workPlan:
            if let workPlan = session.agent.state.activeTask?.workPlan {
                WorkPlanCard(
                    plan: workPlan,
                    isExecuting: isExecuting,
                    bindsReturnShortcut: bindsReturnShortcut,
                    matchedGlass: SageDesign.Glass.MatchedSpec(
                        id: SageDesign.Glass.workPlanCardMatchID,
                        namespace: planGlassNamespace
                    ),
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
                    bindsReturnShortcut: bindsReturnShortcut,
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
                    bindsReturnShortcut: bindsReturnShortcut,
                    onContinue: { Task { await session.agent.confirmToolRoundLimit() } },
                    onFinish: { Task { await session.agent.finishToolRoundLimit() } }
                )
            }

        case .toolApproval:
            toolApprovalChrome(bindsReturnShortcut: bindsReturnShortcut)

        case .reviewFailed:
            if case .reviewFailed(_, let message) = session.agent.state.pendingPrompt {
                ReviewFailedCard(
                    message: message,
                    bindsReturnShortcut: bindsReturnShortcut,
                    onRetry: { Task { await session.agent.retryFailedReview() } },
                    onAccept: { Task { await session.agent.acceptFailedReview() } }
                )
            }

        case .reviewMustFix:
            if case .reviewMustFix(_, let message) = session.agent.state.pendingPrompt {
                ReviewFindingsCard(
                    message: message,
                    mode: isExecuting
                        ? .continuing
                        : .resumeMustFix(
                            onContinue: { Task { await session.agent.resumeMustFixReview() } },
                            onKeep: { Task { await session.agent.acceptMustFixReview() } }
                        ),
                    bindsReturnShortcut: bindsReturnShortcut
                )
            }

        case .reviewOptional:
            if case .reviewOptional(_, let message) = session.agent.state.pendingPrompt {
                ReviewFindingsCard(
                    message: message,
                    mode: .optional(
                        onImprove: { Task { await session.agent.applyOptionalReview() } },
                        onKeep: { Task { await session.agent.acceptOptionalReview() } }
                    ),
                    bindsReturnShortcut: bindsReturnShortcut
                )
            }

        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    func toolApprovalChrome(bindsReturnShortcut: Bool) -> some View {
        if case .toolApproval(_, let name, let args, let title) = session.agent.state.pendingPrompt {
            let requirement = authorizationRequirement(name: name, argumentsJSON: args)
            ToolApprovalCard(
                title: title,
                toolName: name,
                argumentsJSON: args,
                authorizationSummary: requirement?.userFacingSummary,
                authorizationPrompt: requirement?.userFacingPrompt,
                remainingCount: session.agent.remainingApprovalCount,
                bindsReturnShortcut: bindsReturnShortcut,
                onAllowOnce: { Task { await session.agent.confirmToolApproval(scope: .once) } },
                onAllowSession: { Task { await session.agent.confirmToolApproval(scope: .task) } },
                onAllowTool: { Task { await session.agent.confirmToolApproval(scope: .always) } },
                onSkip: { Task { await session.agent.skipToolApproval() } }
            )
        }
    }

    func authorizationRequirement(
        name: String,
        argumentsJSON: String
    ) -> ToolAuthorizationRequirement? {
        ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: session.agent.state.pathGuardPolicy,
            skills: session.agent.host.catalogSkills,
            mcpTools: appState.mcpHub.mcpTools
        )
    }

    /// Failure is a decision moment (Retry / Settings / Dismiss), so it gets
    /// the same glass-card treatment as every other decision — not a bare
    /// status row.
    func failureAccessory(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            HStack(spacing: SageDesign.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .sageFont(type.body, weight: .semibold)
                    .foregroundStyle(SageDesign.Palette.danger)
                Text("Something went wrong")
                    .sageFont(type.body, weight: .semibold)
                    .foregroundStyle(.primary)
            }
            .accessibilityAddTraits(.isHeader)

            Text(message)
                .sageFont(type.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.small) {
                Button {
                    Task { await session.agent.dismissFailure() }
                } label: {
                    Text("Dismiss")
                }
                // Esc ownership during failure: the composer's onKeyPress
                // consumes Esc while suggestions are open (.handled), so this
                // cancelAction only sees Esc when nothing closer wants it —
                // gating on composer focus would leave Esc dead instead.
                .sageShortcut(.cancelAction, enabled: true)
                .buttonStyle(.glass)
                .controlSize(.regular)
                .help(
                    session.agent.state.hasPendingPlan
                        ? "Abandon the pending plan"
                        : "Dismiss this error"
                )

                if looksLikeConfigurationError(message) {
                    Button {
                        NotificationCenter.default.post(name: .sageOpenSettings, object: nil)
                    } label: {
                        Text("Open Settings")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                }

                Spacer(minLength: 0)

                if session.agent.canRetryFailure {
                    Button {
                        stickToBottom = true
                        Task { await session.agent.retryLastFailure() }
                    } label: {
                        Text("Retry")
                    }
                    // Return belongs to the composer when the user is typing —
                    // same gate as the confirmation cards above.
                    .sageShortcut(.defaultAction, enabled: !composerFocused)
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                    .disabled(session.agent.state.isBusy)
                }
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Something went wrong")
    }

    @ViewBuilder
    func eventBubble(_ event: AgentEvent, toolIndex: ToolResultIndex) -> some View {
        switch event.kind {
        case .userInput:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                turnTimestamp(event.createdAt)
                if !event.attachments.isEmpty {
                    AttachmentChipBar(
                        attachments: event.attachments,
                        selectedID: nil,
                        showsRemove: false
                    )
                }
                if !event.content.isEmpty {
                    Text(event.content)
                        .sageFont(type.input)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Reading-canvas content stays passive — same surface
                        // language as tool chips, no glass.
                        .sageToolChipSurface()
                        .textSelection(.enabled)
                }
            }

        case .assistantResponse:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                turnTimestamp(event.createdAt)
                if !event.content.isEmpty {
                    // The just-streamed reply starts expanded so the ending the
                    // user was reading doesn't snap shut at commit; scrolling
                    // back later materializes older replies collapsed.
                    MarkdownContentView(
                        markdown: event.content,
                        collapsible: true,
                        initiallyExpanded: isLatestAssistantReply(event),
                        appearsSoftly: true
                    )
                    .contextMenu {
                        // Collapsed replies hide their text — whole-source
                        // copy is the one action selection can't cover.
                        Button("Copy Reply") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(event.content, forType: .string)
                        }
                    }
                }
                if let changes = event.workspaceChanges, !changes.isEmpty {
                    WorkspaceChangesView(changes: changes)
                }
                if let calls = event.toolCalls, !calls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calls, id: \.id) { call in
                            ToolCallView(
                                name: call.name,
                                argumentsJSON: call.argumentsJSON,
                                titleOverride: Self.loadedSkillTitle(for: call),
                                status: toolIndex.status(
                                    for: call.id,
                                    isBusy: session.agent.state.isBusy
                                ),
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

    /// Turn-boundary marker: time of day (or date + time for older turns).
    @ViewBuilder
    func turnTimestamp(_ date: Date) -> some View {
        Group {
            if Calendar.current.isDateInToday(date) {
                Text(date, format: .dateTime.hour().minute())
            } else {
                Text(date, format: .dateTime.month().day().hour().minute())
            }
        }
        .sageMicro(type.micro)
        .foregroundStyle(.tertiary)
    }

    func looksLikeConfigurationError(_ message: String) -> Bool {
        AppState.looksLikeConfigurationError(message, isConfigured: appState.settings.isConfigured)
    }

    /// True when this reply is the transcript's last event — i.e. the one the
    /// user just watched stream in.
    private func isLatestAssistantReply(_ event: AgentEvent) -> Bool {
        displayEvents.last?.id == event.id
    }

    func scrollToLatest(using proxy: ScrollViewProxy) {
        // A long-transcript jump reads as a teleport on a fixed ease; the
        // critically damped streaming spring carries the travel instead.
        if let animation = SageDesign.Motion.streamingScroll {
            withAnimation(animation) {
                proxy.scrollTo("phase-accessory", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("phase-accessory", anchor: .bottom)
        }
    }

    func scrollToLatestStreaming(using proxy: ScrollViewProxy) {
        if let animation = SageDesign.Motion.streamingScroll {
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
