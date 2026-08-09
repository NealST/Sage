//
//  ProjectPanelActions.swift
//  Sage
//

import AppKit

/// AppKit panels for Open / Create Project.
enum ProjectPanelActions {
    /// Compact path for chrome / menus (`~/…`).
    static func displayPath(_ absolute: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if absolute == home { return "~" }
        if absolute.hasPrefix(home + "/") {
            return "~" + absolute.dropFirst(home.count)
        }
        return absolute
    }

    @MainActor
    static func pickDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = "Choose"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func promptCreateProject() -> (parent: URL, name: String, gitInit: Bool)? {
        guard let parent = pickDirectory(message: "Choose a parent folder for the new project") else {
            return nil
        }

        let alert = NSAlert()
        alert.messageText = "Create Project"
        alert.informativeText = "Enter a folder name under \(parent.lastPathComponent)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.placeholderString = "project-name"
        let gitButton = NSButton(
            checkboxWithTitle: "Initialize git repository",
            target: nil,
            action: nil
        )
        gitButton.state = .on

        let stack = NSStackView(views: [nameField, gitButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return (parent, name, gitButton.state == .on)
    }
}
