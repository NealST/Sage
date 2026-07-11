//
//  AgentChatView.swift
//  Sage
//

import SwiftUI

struct AgentChatView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isInputFocused: Bool

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            transcript
            Divider().opacity(0.35)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusInputSoon() }
        .onReceive(NotificationCenter.default.publisher(for: .sageFocusHUDInput)) { _ in
            focusInputSoon()
        }
        .onChange(of: appState.isHUDVisible) { _, visible in
            if visible { focusInputSoon() }
        }
        .onChange(of: appState.agent.activeSessionID) { _, _ in
            focusInputSoon()
        }
        .onChange(of: appState.agent.phase) { _, phase in
            switch phase {
            case .awaitingConfirmation:
                isInputFocused = false
            case .thinking, .executing:
                break
            default:
                focusInputSoon()
            }
        }
    }

    private var header: some View {
        HStack {
            Text(appState.agent.activeSession?.title ?? "Sage")
                .font(.system(size: SageDesign.Typography.titleSize, weight: .semibold))
            Spacer()
            if case .awaitingConfirmation = appState.agent.phase {
                Text("Awaiting confirmation")
                    .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Button {
                NotificationCenter.default.post(name: .sageOpenSettings, object: nil)
            } label: {
                Image(systemName: SageDesign.Symbol.settings)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.md)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SageDesign.Spacing.md) {
                    ForEach(displayMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    phaseAccessory
                        .id("phase-accessory")
                }
                .padding(SageDesign.Spacing.lg)
            }
            .onChange(of: appState.agent.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("phase-accessory", anchor: .bottom)
                }
            }
            .onChange(of: appState.agent.phase) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("phase-accessory", anchor: .bottom)
                }
            }
        }
    }

    /// Hide raw tool-call assistant blobs that only exist for API wire format noise when content duplicates plan.
    private var displayMessages: [ChatMessage] {
        appState.agent.messages.filter { message in
            if message.role == .tool { return true }
            if message.role == .assistant, message.toolCalls != nil {
                return true // show plan summary line
            }
            return message.role == .user || message.role == .assistant
        }
    }

    @ViewBuilder
    private var phaseAccessory: some View {
        switch appState.agent.phase {
        case .thinking:
            HStack(spacing: SageDesign.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Thinking…")
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .foregroundStyle(.secondary)
            }

        case .awaitingConfirmation(let plan), .executing(let plan):
            PlanCardView(
                plan: plan,
                isExecuting: {
                    if case .executing = appState.agent.phase { return true }
                    return false
                }(),
                onConfirm: {
                    Task { await appState.agent.confirmPendingPlan() }
                },
                onCancel: {
                    appState.agent.cancelPendingPlan()
                }
            )

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: SageDesign.Typography.bodySize))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

        case .idle, .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            Text(message.content)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .assistant:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                if !message.content.isEmpty {
                    MarkdownContentView(markdown: message.content)
                }
                if let calls = message.toolCalls, !calls.isEmpty {
                    FlowToolPills(names: calls.map(\.name))
                }
            }

        case .tool:
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .semibold))
                Text(toolPillTitle(message))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .foregroundStyle(.secondary)

        case .system:
            EmptyView()
        }
    }

    private func toolPillTitle(_ message: ChatMessage) -> String {
        if message.content.hasPrefix("ERROR:") {
            return "Tool failed"
        }
        return String(message.content.prefix(80))
    }

    private var composer: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: SageDesign.Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                TextField("Ask Sage…", text: $appState.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: SageDesign.Typography.inputSize))
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .disabled(blocksTyping)
                    .onSubmit {
                        guard !blocksSubmit else { return }
                        submit()
                    }

                if !appState.draft.isEmpty && !blocksSubmit {
                    Text("Submit ⏎")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            HStack {
                Text(appState.settings.model)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                if case .awaitingConfirmation = appState.agent.phase {
                    Text("Run or Cancel the pending plan")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.md)
    }

    private var blocksTyping: Bool {
        switch appState.agent.phase {
        case .thinking, .executing: return true
        default: return false
        }
    }

    private var blocksSubmit: Bool {
        switch appState.agent.phase {
        case .thinking, .executing, .awaitingConfirmation: return true
        default: return false
        }
    }

    private func submit() {
        let trimmed = appState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.clearDraft()
        appState.agent.resetPhaseToIdle()
        Task { await appState.agent.submit(trimmed) }
    }

    private func focusInputSoon() {
        DispatchQueue.main.async {
            if case .awaitingConfirmation = appState.agent.phase { return }
            isInputFocused = true
        }
    }
}

/// Simple wrapping pill row without a flow layout dependency.
private struct FlowToolPills: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Text(name.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .foregroundStyle(.secondary)
            }
        }
    }
}
