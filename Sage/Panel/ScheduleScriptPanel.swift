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
    @FocusState private var commandFocused: Bool

    init(initial: ScheduleScriptDraft) {
        self.initial = initial
        _command = State(initialValue: initial.command)
        _workingDirectory = State(initialValue: ".")
        _presetInsert = State(initialValue: initial.cadencePresetInsert)
    }

    var body: some View {
        SkillTipChrome.row {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Run a script")
                        .font(.system(size: type.caption, weight: .medium))
                    Spacer(minLength: SageDesign.Spacing.sm)
                    Text(scopeLabel)
                        .font(.system(size: type.micro))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: SageDesign.Spacing.sm) {
                    Text("Command")
                        .font(.system(size: type.micro, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)

                    TextField("./scripts/daily.sh", text: $command, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: type.body, design: .monospaced))
                        .lineLimit(1...3)
                        .focused($commandFocused)
                        .accessibilityLabel("Command")

                    Button("Choose File…") {
                        chooseFile()
                    }
                    .controlSize(.small)
                    .disabled(session.agent.blocksNewInput)
                }

                HStack(spacing: SageDesign.Spacing.sm) {
                    Text("Working dir")
                        .font(.system(size: type.micro, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)

                    TextField(".", text: $workingDirectory)
                        .textFieldStyle(.plain)
                        .font(.system(size: type.body, design: .monospaced))
                        .accessibilityLabel("Working directory")
                        .help("Relative to this window’s sandbox. Must stay inside PathGuard.")

                    Button("Choose…") {
                        chooseWorkingDirectory()
                    }
                    .controlSize(.small)
                    .disabled(session.agent.blocksNewInput)
                }

                if !workingDirectoryIsAllowed {
                    Text("Working directory must exist inside this window’s sandbox.")
                        .font(.system(size: type.micro))
                        .foregroundStyle(.red)
                        .padding(.leading, 88)
                }

                HStack(alignment: .firstTextBaseline, spacing: SageDesign.Spacing.sm) {
                    Text("When")
                        .font(.system(size: type.micro, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)

                    HStack(spacing: 6) {
                        ForEach(ScheduleCadenceParser.presets) { preset in
                            cadenceChip(preset)
                        }
                    }
                }

                HStack(spacing: SageDesign.Spacing.sm) {
                    Button(runOnceNow ? "Save and run" : "Save") {
                        save()
                    }
                    .font(.system(size: type.micro, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(!canSave)
                    .help("Save this timetable. It runs in this window’s sandbox.")

                    Button("Cancel") {
                        cancel()
                    }
                    .font(.system(size: type.micro, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Toggle(isOn: $runOnceNow) {
                        Text("Run once now")
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: type.micro))
                    .help("Run immediately after save. The timetable still fires at the scheduled time.")
                    .accessibilityLabel("Run once now")

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.sm)
        .onAppear {
            commandFocused = true
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

    private func cadenceChip(_ preset: ScheduleCadenceParser.Preset) -> some View {
        let selected = preset.insert == presetInsert
        return Button(preset.insert) {
            presetInsert = preset.insert
        }
        .buttonStyle(.plain)
        .font(.system(size: type.micro, weight: selected ? .semibold : .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(selected ? 0.14 : 0.05))
        )
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(preset.description)
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
        guard picked == root || picked.hasPrefix(root + "/") else { return }

        let policy: PathGuard.Policy = session.agent.state.focusedProject == nil
            ? .home
            : .project(root: sandboxRoot)
        var display = PathGuard.displayPath(picked, policy: policy)
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
            let ok = await appState.schedules.save(record, runOnceNow: trial)
            if !ok, let message = appState.schedules.lastError {
                session.agent.reportFailure(message)
            }
        }
    }

    private func cancel() {
        session.skills.scriptScheduleDraft = nil
    }
}
