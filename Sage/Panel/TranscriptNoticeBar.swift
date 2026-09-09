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
        } else if let hint = session.agent.state.contextHint {
            contextChip(hint)
                .sageGlassMaterialize()
                .transition(noticeTransition)
        }
    }

    private var noticeTransition: AnyTransition {
        SageDesign.Glass.appearTransition
    }

    private func topicDriftChip(_ offer: TopicDriftOffer) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: type.micro, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(offer.message)
                .font(.system(size: type.micro, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Start Fresh") {
                Task { await session.agent.startFresh() }
            }
            .controlSize(.small)
            .buttonStyle(.glass)
            .font(.system(size: type.micro, weight: .semibold))
            .disabled(!session.agent.canStartFresh)
            .help(
                session.agent.state.isBusy
                    ? "Wait until this turn finishes before starting a new task"
                    : "Start a clean task in this window"
            )
            .accessibilityLabel("Start Fresh")
            .accessibilityHint("Starts a new task with your last message")

            Button("Keep going", systemImage: "xmark") {
                session.agent.dismissTopicDriftOffer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.small)
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
                .font(.system(size: type.micro, weight: .semibold))
                .accessibilityHidden(true)
            Text(hint)
                .font(.system(size: type.micro, weight: .medium))
                .lineLimit(1)
                .accessibilityLabel(hint)
            Spacer(minLength: 4)
            Button("Don’t reuse") {
                session.agent.dismissContextHint()
            }
            .controlSize(.small)
            .buttonStyle(.glass)
            .help("Next request starts without this prior context")
            .accessibilityHint("Next request starts without this prior context")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.bottom, SageDesign.Spacing.small)
        .accessibilityElement(children: .contain)
    }
}
