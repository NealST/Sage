//
//  ToolCallView.swift
//  Sage
//

import SwiftUI

/// Expandable tool-call chip used in the transcript and plan card.
/// File edits (`write_text_file`) expand to a before/after unified diff when possible.
struct ToolCallView: View {
    let name: String
    let argumentsJSON: String
    var titleOverride: String?
    var status: StepStatus?
    /// Completed tool result (may embed a write-file diff payload).
    var resultContent: String?
    /// Compare proposed content against the file on disk (plan confirmation).
    /// Do not enable for historical transcript chips after the write already landed.
    var previewAgainstDisk: Bool = false
    /// When true (plan awaiting confirmation), start expanded for file edits.
    var startExpandedIfFileEdit: Bool = false
    /// Plan confirmation mode: mutating steps read warmer than read-only ones
    /// so their weight is scannable before Run.
    var highlightsSideEffects: Bool = false

    @Environment(\.pathGuardPolicy) var pathGuardPolicy
    @Environment(\.sageTypography) var type
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var expanded: Bool
    /// `nil` = still loading; `.absent` = no file; `.text` / `.unreadable` once loaded.
    @State var diskState: DiskBeforeState = .pending

    var isMutatingStep: Bool {
        highlightsSideEffects && ToolDefinition.requiresConfirmation(forToolNamed: name)
    }

    enum DiskBeforeState: Equatable {
        case pending
        case absent
        case unreadable
        case text(String)
    }

    init(
        name: String,
        argumentsJSON: String,
        titleOverride: String? = nil,
        status: StepStatus? = nil,
        resultContent: String? = nil,
        previewAgainstDisk: Bool = false,
        startExpandedIfFileEdit: Bool = false,
        highlightsSideEffects: Bool = false
    ) {
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.titleOverride = titleOverride
        self.status = status
        self.resultContent = resultContent
        self.previewAgainstDisk = previewAgainstDisk
        self.startExpandedIfFileEdit = startExpandedIfFileEdit
        self.highlightsSideEffects = highlightsSideEffects
        let model = ToolCallPresentation.model(
            name: name,
            argumentsJSON: argumentsJSON,
            titleOverride: titleOverride,
            policy: .home
        )
        let shouldExpand: Bool
        if case .fileEdit = model.body, startExpandedIfFileEdit {
            shouldExpand = true
        } else {
            shouldExpand = false
        }
        _expanded = State(initialValue: shouldExpand)
    }

    var model: ToolCallPresentation.Model {
        ToolCallPresentation.model(
            name: name,
            argumentsJSON: argumentsJSON,
            titleOverride: titleOverride,
            policy: pathGuardPolicy
        )
    }

    var writePayload: WriteFileDiffPayload? {
        resultContent.flatMap(WriteFileResultCodec.payload(in:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded, model.isExpandable {
                previewBody
                    .transition(ToolChipChrome.expandTransition)
            }
        }
        .sageToolChipSurface(warning: isMutatingStep)
        .environment(\.openURL, PathTextSupport.openURLAction)
        .task(id: diskPreviewTaskID) {
            await loadDiskBeforeIfNeeded()
        }
    }

    var diskPreviewTaskID: String {
        guard previewAgainstDisk,
              writePayload == nil,
              case let .fileEdit(path, _, _) = model.body
        else { return "" }
        return path
    }

    var header: some View {
        Button {
            guard model.isExpandable else { return }
            withAnimation(SageDesign.Motion.expandAnimation) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if let status {
                    statusIcon(status)
                        .frame(width: 14, alignment: .center)
                } else {
                    Image(systemName: iconName)
                        .sageFont(type.icon, weight: .semibold)
                        // Same leading column as the status icon so titles
                        // align whether or not a status has arrived yet.
                        .frame(width: 14, alignment: .center)
                }

                Text(model.title)
                    .sageMicro(type.micro, weight: .medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isMutatingStep {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .sageFont(type.icon, weight: .semibold)
                        .foregroundStyle(SageDesign.Palette.warning)
                        .help("This step changes your Mac")
                }

                if model.isExpandable {
                    Image(systemName: "chevron.down")
                        .sageFont(type.icon, weight: .semibold)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolChipHeaderButtonStyle())
        .foregroundStyle(.secondary)
        .disabled(!model.isExpandable)
        .accessibilityLabel("\(model.title), \(statusAccessibilityText)")
        .accessibilityValue(model.isExpandable ? (expanded ? "Expanded" : "Collapsed") : "")
        .help(model.isExpandable ? (expanded ? "Hide details" : "Show tool details") : model.title)
        .animation(SageDesign.Motion.expandAnimation, value: expanded)
    }

    /// Chip status for VoiceOver — the icon grammar is visual-only otherwise.
    private var statusAccessibilityText: String {
        switch status {
        case .pending: return "waiting"
        case .running: return "running"
        case .succeeded: return "succeeded"
        case .failed: return "failed"
        case .skipped: return "skipped"
        case nil: return "not started"
        }
    }

    @ViewBuilder var previewBody: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            switch model.body {
            case let .fileEdit(path, content, language):
                fileEditPreview(path: path, content: content, language: language)

            case let .text(label, value):
                labeledText(label: label, value: value)

            case let .fields(pairs):
                fieldsPreview(pairs)

            case .empty:
                EmptyView()
            }
        }
        .padding(.bottom, 10)
    }
}
