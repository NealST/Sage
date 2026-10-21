import Foundation

/// Isolated streaming token buffer for SwiftUI.
///
/// Kept as its own `@Observable` so SSE updates do not invalidate
/// `AgentRuntime` / workspace chrome / composer observers.
@MainActor
@Observable
final class StreamingPlayback {
    private(set) var text: String = ""
    private(set) var thinking: String = ""
    /// Plan JSON is hidden; hold the work-plan card's seat until it lands.
    private(set) var isReservingWorkPlan = false
    /// Coarse scroll trigger: `lineCount * 1000 + lengthBucket` (bucket = utf16 count / 80).
    private(set) var scrollThrottleKey: Int = 0

    private var lineCount = 1

    var isActive: Bool { !text.isEmpty || !thinking.isEmpty || isReservingWorkPlan }

    func apply(_ text: String) {
        updateLineCount(for: text)
        self.text = text
        bumpScrollKey(for: text)
    }

    func applyThinking(_ text: String) {
        thinking = text
        bumpScrollKey(for: text)
    }

    func setReservingWorkPlan(_ reserved: Bool) {
        guard isReservingWorkPlan != reserved else { return }
        isReservingWorkPlan = reserved
    }

    func clear() {
        text = ""
        thinking = ""
        isReservingWorkPlan = false
        lineCount = 1
        scrollThrottleKey = 0
    }

    private func bumpScrollKey(for text: String) {
        scrollThrottleKey = lineCount &* 1_000 &+ (text.utf16.count / 80)
    }

    private func updateLineCount(for text: String) {
        if text.hasPrefix(self.text) {
            let added = text[self.text.endIndex...]
            for char in added where char == "\n" {
                lineCount += 1
            }
            return
        }
        if self.text.hasPrefix(text) {
            // Truncation / rewrite — recount.
            lineCount = 1
            for char in text where char == "\n" {
                lineCount += 1
            }
            return
        }
        lineCount = 1
        for char in text where char == "\n" {
            lineCount += 1
        }
    }
}
