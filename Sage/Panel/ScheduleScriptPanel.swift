//
//  ScheduleScriptPanel.swift
//  Sage
//
//  `/schedule-script` — command + when, scoped to the current window.
//

import AppKit
import SwiftUI

struct ScheduleScriptPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type

    let initial: ScheduleScriptDraft

    @State private var command: String
    @State private var workingDirectory: String
    @State private var presetInsert: String
    @State private var runOnceNow = false
    @State private var workingDirectoryIsAllowed = true
    @State private var filePickError: String?
    private enum Field { case command, workingDirectory }
    @FocusState private var focusedField: Field?
    /// Label column width — scales with Dynamic Type alongside the micro labels.
    @ScaledMetric(relativeTo: .caption) private var labelColumnWidth: CGFloat = 80

    init(initial: ScheduleScriptDraft) {
        self.initial = initial
        _command = State(initialValue: initial.command)
        _workingDirectory = State(initialValue: ".")
        _presetInsert = State(initialValue: initial.cadencePresetInsert)
    }

    var body: some View {
        SkillTipChrome.row {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Run a script")
                        .sageFont(type.caption, weight: .medium)
                    Spacer(minLength: SageDesign.Spacing.small)
                    Text(scopeLabel)
                        .sageMicro(type.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: SageDesign.Spacing.small) {
                    Text("Command")
                        .sageMicro(type.micro, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(width: labelColumnWidth, alignment: .leading)

                    TextField("./scripts/daily.sh", text: $command, axis: .vertical)
                        .textFieldStyle(.plain)
                        .sageFont(type.body, design: .monospaced)
                        .lineLimit(1...3)
                        .focused($focusedField, equals: .command)
                        .sageFieldChrome(focused: focusedField == .command)
                        .accessibilityLabel("Command")

                    Button("Choose File…") {
                        chooseFile()
                    }
                    .controlSize(.small)
                    .disabled(session.agent.blocksNewInput)
                }

                HStack(spacing: SageDesign.Spacing.small) {
                    Text("Working dir")
                        .sageMicro(type.micro, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(width: labelColumnWidth, alignment: .leading)

                    TextField(".", text: $workingDirectory)
                        .textFieldStyle(.plain)
                        .sageFont(type.body, design: .monospaced)
                        .focused($focusedField, equals: .workingDirectory)
                        .sageFieldChrome(focused: focusedField == .workingDirectory)
                        .accessibilityLabel("Working directory")
                        .help("Relative to this window’s sandbox. Must stay inside PathGuard.")

                    Button("Choose…") {
                        chooseWorkingDirectory()
                    }
                    .controlSize(.small)
                    .disabled(session.agent.blocksNewInput)
                }

                if let filePickError {
                    HStack(spacing: SageDesign.Spacing.small) {
                        Color.clear.frame(width: labelColumnWidth)
                        Text(filePickError)
                            .sageMicro(type.micro)
                            .foregroundStyle(SageDesign.Palette.dangerText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !workingDirectoryIsAllowed {
                    HStack(spacing: SageDesign.Spacing.small) {
                        // Alignment spacer matching the label column above.
                        Color.clear.frame(width: labelColumnWidth)
                        Text("Working directory must exist inside this window’s sandbox.")
                            .sageMicro(type.micro)
                            .foregroundStyle(SageDesign.Palette.dangerText)
                    }
                }

                HStack(spacing: SageDesign.Spacing.small) {
                    Text("When")
                        .sageMicro(type.micro, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(width: labelColumnWidth, alignment: .leading)

                    Picker("When", selection: $presetInsert) {
                        ForEach(ScheduleCadenceParser.presets) { preset in
                            Text(preset.insert).tag(preset.insert)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("When")
                }

                HStack(spacing: SageDesign.Spacing.small) {
                    Toggle(isOn: $runOnceNow) {
                        Text("Run once now")
                    }
                    .toggleStyle(.checkbox)
                    .sageMicro(type.micro)
                    .help("Run immediately after save. The timetable still fires at the scheduled time.")
                    .accessibilityLabel("Run once now")

                    Spacer(minLength: 0)

                    Button("Cancel") {
                        cancel()
                    }
                    .controlSize(.small)
                    .help("Discard this draft (Esc)")

                    // Primary action — prominent, rightmost per macOS convention.
                    Button(runOnceNow ? "Save and Run" : "Save") {
                        save()
                    }
                    .sageGlassProminentButton(.small)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSave)
                    .help("Save this timetable (⌘S). It runs in this window’s sandbox.")
                }
            }
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.small)
        .onAppear {
            focusedField = .command
            refreshWorkingDirectoryAllowed()
        }
        .onChange(of: workingDirectory) { _, _ in
            refreshWorkingDirectoryAllowed()
        }
        .onExitCommand(perform: cancel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule a script in \(scopeLabel)")
    }

    private var scopeLabel: String {
        if let project = session.agent.state.focusedProject {
            return "This Project · \(project.name)"
        }
        return "General"
    }

    private var sandboxRoot: URL {
        session.agent.state.focusedProject?.rootURL
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private var canSave: Bool {
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ScheduleCadenceParser.cadence(fromPresetInsert: presetInsert) != nil
            && workingDirectoryIsAllowed
    }

    private var pathGuardPolicy: PathGuard.Policy {
        session.agent.state.focusedProject == nil
            ? .home
            : .project(root: sandboxRoot)
    }

    private func refreshWorkingDirectoryAllowed() {
        workingDirectoryIsAllowed =
            (try? ScheduleService.resolveWorkingDirectory(workingDirectory, policy: pathGuardPolicy)) != nil
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = sandboxRoot
        panel.prompt = "Choose"
        panel.message = "Pick a file inside this window’s sandbox."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let root = sandboxRoot.resolvingSymlinksInPath().path
        let picked = url.resolvingSymlinksInPath().path
        guard picked == root || picked.hasPrefix(root + "/") else {
            filePickError = "That file is outside this window’s sandbox. Pick one inside \(PathGuard.displayPath(root, policy: pathGuardPolicy))."
            return
        }
        filePickError = nil

        var display = PathGuard.displayPath(picked, policy: pathGuardPolicy)
        if display.contains(" ") {
            display = "\"\(display)\""
        }
        command = display
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sandboxRoot
        panel.prompt = "Choose"
        panel.message = "Pick a folder inside this window’s sandbox."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let display = PathGuard.displayPath(url.path, policy: pathGuardPolicy)
        workingDirectory = display
        refreshWorkingDirectoryAllowed()
    }

    private func save() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let cadence = ScheduleCadenceParser.cadence(fromPresetInsert: presetInsert),
              workingDirectoryIsAllowed
        else { return }
        let record = ScheduleRecord.script(
            command: trimmed,
            cadence: cadence,
            projectID: session.agent.state.focusedProject?.id,
            workingDirectory: workingDirectory
        )
        let trial = runOnceNow
        session.skills.scriptScheduleDraft = nil
        Task {
            let didSave = await appState.schedules.save(record, runOnceNow: trial)
            if !didSave, let message = appState.schedules.lastError {
                session.agent.reportFailure(message)
            }
        }
    }

    private func cancel() {
        session.skills.scriptScheduleDraft = nil
    }
}

/// Plain-style form fields need visible focus state for Full Keyboard Access —
/// same chrome idiom as SageInlineSearchField: quiet fill + system focus color.
private struct SageFormFieldChrome: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, SageDesign.Spacing.medium)
            .padding(.vertical, SageDesign.Spacing.compactChipVertical)
            .background(
                RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                    .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 1.5)
                    .opacity(focused ? 1 : 0)
            )
    }
}

private extension View {
    func sageFieldChrome(focused: Bool) -> some View {
        modifier(SageFormFieldChrome(focused: focused))
    }
}
