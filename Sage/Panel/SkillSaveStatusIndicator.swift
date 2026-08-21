//
//  SkillSaveStatusIndicator.swift
//  Sage
//
//  Composer status-bar chip for background skill create/enhance jobs.
//  Quiet capsule chrome (matches WorkspaceChrome status pills); popover for detail.
//

import SwiftUI

struct SkillSaveStatusIndicator: View {
    @Environment(AgentSession.self) private var session
    @State private var showPopover = false

    private var jobs: [SkillSaveJob] {
        session.skills.saveJobs
    }

    private var aggregate: AggregateState {
        if jobs.contains(where: { if case .running = $0.status { return true }; return false }) {
            return .running
        }
        if jobs.contains(where: { if case .failed = $0.status { return true }; return false }) {
            return .failed
        }
        return .succeeded
    }

    private enum AggregateState {
        case running, succeeded, failed
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            chipLabel
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(chipFill)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Skill save status")
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            popoverContent
        }
    }

    private var chipLabel: some View {
        HStack(spacing: 5) {
            chipIcon
            Text(chipTitle)
                .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(chipForeground)
    }

    @ViewBuilder
    private var chipIcon: some View {
        switch aggregate {
        case .running:
            ProgressView()
                .controlSize(.mini)

        case .succeeded:
            Image(systemName: SageDesign.Symbol.stepSuccess)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

        case .failed:
            Image(systemName: SageDesign.Symbol.stepFailed)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var chipTitle: String {
        switch aggregate {
        case .running:
            let count = jobs.filter { if case .running = $0.status { return true }; return false }.count
            return count > 1 ? "Saving \(count)…" : "Saving…"

        case .succeeded:
            return "Saved"

        case .failed:
            let count = jobs.filter { if case .failed = $0.status { return true }; return false }.count
            return count > 1 ? "\(count) failed" : "Save failed"
        }
    }

    private var chipForeground: Color {
        switch aggregate {
        case .running, .succeeded:
            return .secondary

        case .failed:
            return .orange
        }
    }

    private var chipFill: Color {
        switch aggregate {
        case .running, .succeeded:
            return Color.primary.opacity(SageDesign.Chrome.pillFillOpacity)

        case .failed:
            return Color.orange.opacity(0.14)
        }
    }

    private var accessibilityLabel: String {
        switch aggregate {
        case .running:
            let count = jobs.filter { if case .running = $0.status { return true }; return false }.count
            return "Skill save in progress, \(count) running. Click for details."

        case .failed:
            let count = jobs.filter { if case .failed = $0.status { return true }; return false }.count
            return "Skill save failed, \(count) need attention. Click for details."

        case .succeeded:
            return "Skill saved. Click for details."
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Skill saves")
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, SageDesign.Spacing.medium)
                .padding(.top, SageDesign.Spacing.medium)
                .padding(.bottom, SageDesign.Spacing.small)

            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                if index > 0 {
                    Divider()
                        .opacity(SageDesign.Chrome.dividerOpacity)
                        .padding(.leading, 36)
                }
                jobRow(job)
            }
        }
        .frame(width: 280)
        .padding(.bottom, SageDesign.Spacing.small)
    }

    @ViewBuilder
    private func jobRow(_ job: SkillSaveJob) -> some View {
        HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
            jobStatusIcon(job.status)
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(jobDisplayTitle(job))
                    .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(jobDetail(job))
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(detailForeground(job.status))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if case .failed = job.status {
                Button {
                    session.skills.dismissSkillSaveJob(job.id)
                    if session.skills.saveJobs.isEmpty {
                        showPopover = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, SageDesign.Spacing.medium)
        .padding(.vertical, 8)
    }

    private func jobDisplayTitle(_ job: SkillSaveJob) -> String {
        job.skillName
    }

    private func jobDetail(_ job: SkillSaveJob) -> String {
        switch job.status {
        case .running:
            switch job.type {
            case .new: return "Creating skill…"
            case .enhance: return "Updating experience…"
            case .merge: return "Merging skills…"
            }

        case .succeeded:
            switch job.type {
            case .new: return "Created"
            case .enhance: return "Updated"
            case .merge: return "Merged"
            }

        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private func jobStatusIcon(_ status: SkillSaveJob.Status) -> some View {
        switch status {
        case .running:
            ProgressView()
                .controlSize(.mini)

        case .succeeded:
            Image(systemName: SageDesign.Symbol.stepSuccess)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

        case .failed:
            Image(systemName: SageDesign.Symbol.stepFailed)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func detailForeground(_ status: SkillSaveJob.Status) -> Color {
        switch status {
        case .running, .succeeded:
            return .secondary

        case .failed:
            return .orange
        }
    }
}
