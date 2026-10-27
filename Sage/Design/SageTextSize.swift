//
//  SageTextSize.swift
//  Sage
//
//  App-level text scaling — macOS offers no Dynamic Type channel, so Sage
//  ships its own discrete scale so people can enlarge chrome and reading
//  text (HIG: support text sizes of at least 200% via custom UI).
//

import Foundation
import Observation

@MainActor
@Observable
final class SageTextSizeSettings {
    static let shared = SageTextSizeSettings()

    /// Discrete steps keep layouts predictable — arbitrary factors break
    /// chip and reading-column rhythm. 1.0 through 2.0 per HIG.
    static let steps: [CGFloat] = [1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

    private static let storageKey = "sage.textSizeScale"

    private(set) var scale: CGFloat

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.storageKey)
        scale = Self.steps.contains(stored) ? stored : 1.0
    }

    /// Snaps to the nearest step before persisting.
    func setScale(_ requested: CGFloat) {
        let nearest = Self.steps.min(by: { abs($0 - requested) < abs($1 - requested) }) ?? 1.0
        guard nearest != scale else { return }
        scale = nearest
        UserDefaults.standard.set(nearest, forKey: Self.storageKey)
    }

    var isDefault: Bool { scale == 1.0 }

    func stepUp() {
        guard let index = Self.steps.firstIndex(of: scale),
              index + 1 < Self.steps.count
        else { return }
        setScale(Self.steps[index + 1])
    }

    func stepDown() {
        guard let index = Self.steps.firstIndex(of: scale), index > 0 else { return }
        setScale(Self.steps[index - 1])
    }

    func reset() {
        setScale(1.0)
    }
}
