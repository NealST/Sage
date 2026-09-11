//
//  TranscriptNoticeBar.swift
//  Sage
//
//  Quiet, non-blocking notices above the transcript (Apple inline-banner density).
//

import SwiftUI

struct TranscriptNoticeBar: View {
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type

    var body: some View {
        if let offer = session.agent.state.topicDriftOffer {
            topicDriftChip(offer)
                .sageGlassMaterialize()
                .transition(noticeTransition)
        } else if showsContextBudgetNotice {
            contextBudgetChip
                .sageGlassMaterialize()
                .transition(noticeTransition)
        } else if let hint = session.agent.state.contextHint {
            contextChip(hint)
                .sageGlassMaterialize()
                .transition(noticeTransition)
        }
    }

    private var noticeTransition: AnyTransition {
        SageDesign.Glass.appearTransition
    }

    /// The budget notice sits between the actionable drift offer and the
    /// resume hint: it persists while occupancy stays high, so it must not
    /// shadow offers, but it outranks the informational resume chip.
    private var showsContextBudgetNotice: Bool {
        guard let occupancy = session.agent.state.contextOccupancy else { return false }
        guard occupancy >= AgentSessionState.contextNoticeThreshold else { return false }
        return session.agent.state.suppressedContextBudgetTaskID != session.agent.state.activeTaskID
    }

    private var contextBudgetChip: some View {
        let percent = Int(((session.agent.state.contextOccupancy ?? 0) * 100).rounded())
        return HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .sageMicro(type.micro, weight: .semibold)
                .foregroundStyle(SageDesign.Palette.warning)
                .accessibilityHidden(true)

            Text("Context is \(percent)% full — early turns may be summarized. Start Fresh frees the window.")
                .sageMicro(type.micro, weight: .medium)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                session.agent.dismissContextBudgetNotice()
            } label: {
                Image(systemName: "xmark")
                    .sageMicro(type.micro, weight: .semibold)
                    .padding(6)
                    .contentShape(Capsule())
            }
            .buttonStyle(SagePressableChipButtonStyle())
            .help("Hide for this task")
            .accessibilityLabel("Hide context warning")
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.bottom, SageDesign.Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context window \(percent) percent full. Early turns may be summarized.")
    }

    private func topicDriftChip(_ offer: TopicDriftOffer) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "plus.square.on.square")
                .sageMicro(type.micro, weight: .semibold)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(offer.message)
                .sageMicro(type.micro, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await session.agent.startFresh() }
            } label: {
                Text("Start Fresh")
                    .sageMicro(type.micro, weight: .semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Capsule())
            }
            .buttonStyle(SagePressableChipButtonStyle())
            .disabled(!session.agent.canStartFresh)
            .help(
                session.agent.state.isBusy
                    ? "Wait until this turn finishes before starting a new task"
                    : "Start a clean task in this window"
            )
            .accessibilityLabel("Start Fresh")
            .accessibilityHint("Starts a new task with your last message")

            Button {
                session.agent.dismissTopicDriftOffer()
            } label: {
                Image(systemName: "xmark")
                    .sageMicro(type.micro, weight: .semibold)
                    .padding(6)
                    .contentShape(Capsule())
            }
            .buttonStyle(SagePressableChipButtonStyle())
            .disabled(session.agent.state.isAcceptingTopicDrift)
            .help("Keep going in this task")
            .accessibilityLabel("Keep going")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.bottom, SageDesign.Spacing.small)
        .accessibilityElement(children: .contain)
    }

    private func contextChip(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .sageMicro(type.micro, weight: .semibold)
                .accessibilityHidden(true)
            Text(hint)
                .sageMicro(type.micro, weight: .medium)
                .lineLimit(1)
                .accessibilityLabel(hint)
            Spacer(minLength: 4)
            Button {
                session.agent.dismissContextHint()
            } label: {
                Text("Don’t reuse")
                    .sageMicro(type.micro, weight: .semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Capsule())
            }
            .buttonStyle(SagePressableChipButtonStyle())
            .help("Next request starts without this prior context")
            .accessibilityHint("Next request starts without this prior context")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.bottom, SageDesign.Spacing.small)
        .accessibilityElement(children: .contain)
    }
}
