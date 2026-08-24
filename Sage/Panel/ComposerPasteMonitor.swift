//
//  ComposerPasteMonitor.swift
//  Sage
//
//  Intercepts ⌘V only when the composer is focused and the pasteboard
//  has files or a screenshot, so text paste still goes to the field.
//

import AppKit
import SwiftUI

struct ComposerPasteMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onPaste: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onPaste = onPaste
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onPaste = onPaste
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        var isEnabled = false
        var onPaste: () -> Bool = { false }
        private var monitor: Any?

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return MainActor.assumeIsolated { self.handle(event) }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled else { return event }
            guard event.modifierFlags.contains(.command) else { return event }
            guard event.charactersIgnoringModifiers?.lowercased() == "v" else { return event }
            guard AttachmentImport.pasteboardHasNonTextPayload() else { return event }
            return onPaste() ? nil : event
        }
    }
}
