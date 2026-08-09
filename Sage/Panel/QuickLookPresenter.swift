//
//  QuickLookPresenter.swift
//  Sage
//

import AppKit
import QuickLookUI

/// Presents an in-app Quick Look panel for local files (images, PDFs, etc.).
@MainActor
final class QuickLookPresenter: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()

    private var urls: [URL] = []
    private weak var previousWindow: NSWindow?
    private weak var previousFirstResponder: NSResponder?

    func preview(url: URL) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolved.path) else { return }
        urls = [resolved]

        // Remember focus so we can restore it when Quick Look closes.
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            previousWindow = window
            previousFirstResponder = window.firstResponder
            window.makeFirstResponder(self)
        }

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.updateController()
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - NSResponder (QLPreviewPanelController)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !urls.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        restorePreviousFocus()
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }

    // MARK: - Focus

    private func restorePreviousFocus() {
        let window = previousWindow
        let responder = previousFirstResponder
        previousWindow = nil
        previousFirstResponder = nil
        urls = []

        guard let window else { return }
        // Bring the agent window back, then restore the prior first responder (often the composer).
        window.makeKeyAndOrderFront(nil)
        if let responder, responder !== self {
            window.makeFirstResponder(responder)
        }
    }
}
