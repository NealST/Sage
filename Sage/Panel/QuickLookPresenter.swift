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
        preview(urls: [url], selectedIndex: 0)
    }

    func preview(urls candidateURLs: [URL], selectedIndex: Int) {
        let resolved = candidateURLs.map {
            $0.resolvingSymlinksInPath().standardizedFileURL
        }
        guard resolved.indices.contains(selectedIndex),
              FileManager.default.fileExists(atPath: resolved[selectedIndex].path)
        else { return }
        let available = resolved.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !available.isEmpty else { return }
        let selectedURL = resolved[selectedIndex]
        urls = available
        let previewIndex = available.firstIndex(of: selectedURL) ?? 0

        // Remember focus so we can restore it when Quick Look closes.
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            previousWindow = window
            previousFirstResponder = window.firstResponder
            window.makeFirstResponder(self)
        }

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.updateController()
        panel.currentPreviewItemIndex = previewIndex
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - NSResponder (QLPreviewPanelController)

    override nonisolated func acceptsPreviewPanelControl(_ panel: QLPreviewPanel?) -> Bool {
        MainActor.assumeIsolated { !urls.isEmpty }
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = self
            panel?.delegate = self
        }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = nil
            panel?.delegate = nil
            restorePreviousFocus()
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel?) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel?, previewItemAt index: Int) -> (any QLPreviewItem)? {
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
