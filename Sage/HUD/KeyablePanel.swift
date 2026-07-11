//
//  KeyablePanel.swift
//  Sage
//

import AppKit

/// Borderless panels return `false` for `canBecomeKey` by default, which blocks text input.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
