//
//  TranscriptNoticeBar.swift
//  Sage
//
//  Quiet, non-blocking notices above the transcript (Apple inline-banner density).
//

import SwiftUI

struct TranscriptNoticeBar: View {
    @Environment(AgentSession.self) private var session
    @Environment(AccessibilitySettings.self) private var accessibility
    @Environment(\.sageTypography) private var type

    var body: some View {
        if let offer = session.agent.state.topicDriftOffer {
            topicDriftChip(offer)
                .transition(noticeTransition)
        } else if let hint = session.agent.state.contextHint {
            contextChip(hint)
                .transition(noticeTransition)
        }
    }

    private var noticeTransition: AnyTransition {
        if accessibility.reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .move(edge: .top))
    }

    private func topicDriftChip(_ offer: TopicDriftOffer) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: type.micro, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(offer.message)
                .font(.system(size: type.micro))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("New Task") {
                Task { await session.agent.acceptTopicDriftOffer() }
            }
            .controlSize(.mini)
            .buttonStyle(.plain)
            .font(.system(size: type.micro, weight: .semibold))
            .disabled(session.agent.state.isAcceptingTopicDrift)
            .help("Move this latest exchange into a new task")
            .accessibilityLabel("New Task")
            .accessibilityHint("Moves the latest exchange into a new task")

            Button {
                session.agent.dismissTopicDriftOffer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.agent.state.isAcceptingTopicDrift)
            .help("Keep going in this task")
            .accessibilityLabel("Keep going")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.bottom, SageDesign.Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    private func contextChip(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: type.micro, weight: .semibold))
                .accessibilityHidden(true)
            Text(hint)
                .font(.system(size: type.micro))
                .lineLimit(1)
                .accessibilityLabel(hint)
            Spacer(minLength: 4)
            Button("Don’t reuse") {
                session.agent.dismissContextHint()
            }
            .controlSize(.mini)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Next request starts without this prior context")
            .accessibilityHint("Next request starts without this prior context")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.bottom, SageDesign.Spacing.sm)
        .accessibilityElement(children: .contain)
    }
}
