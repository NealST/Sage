//
//  MemoryPressureMonitor.swift
//  Sage
//
//  Monitors macOS memory pressure events and notifies subscribers
//  so they can shed caches / unload models when the system is tight.
//

import Foundation

/// Lightweight memory-pressure listener backed by `DispatchSource`.
///
/// Start once at app launch; the monitor runs for the process lifetime.
/// Subscribers receive callbacks on the main queue.
final class MemoryPressureMonitor: @unchecked Sendable {
    static let shared = MemoryPressureMonitor()

    enum PressureLevel: Sendable {
        case normal
        case warning
        case critical
    }

    /// Called on the main queue whenever the pressure level changes.
    var onPressureChange: (@MainActor @Sendable (PressureLevel) -> Void)?

    private let source: DispatchSourceMemoryPressure
    private var lastLevel: PressureLevel = .normal

    private init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data
            let level: PressureLevel
            if event.contains(.critical) {
                level = .critical
            } else if event.contains(.warning) {
                level = .warning
            } else {
                level = .normal
            }
            guard level != self.lastLevel else { return }
            self.lastLevel = level
            if let callback = self.onPressureChange {
                Task { @MainActor in callback(level) }
            }
        }
    }

    func start() {
        source.resume()
    }

    /// Current pressure level (read from the last event).
    var currentLevel: PressureLevel { lastLevel }
}
