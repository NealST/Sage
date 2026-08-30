import Foundation

/// Coalesces SSE token updates to ~30 Hz before writing `StreamingPlayback`.
@MainActor
final class StreamingTextPump {
    private weak var playback: StreamingPlayback?
    private var pendingText: String?
    private var pendingThinking: String?
    private var publishTask: Task<Void, Never>?

    func attach(playback: StreamingPlayback) {
        self.playback = playback
    }

    func publish(_ text: String) {
        pendingText = text
        startPublishLoop()
    }

    func publishThinking(_ text: String) {
        pendingThinking = text
        startPublishLoop()
    }

    func flush(_ text: String) {
        publishTask?.cancel()
        publishTask = nil
        pendingText = nil
        playback?.apply(text)
    }

    func flushThinking(_ text: String) {
        pendingThinking = nil
        playback?.applyThinking(text)
    }

    func clear() {
        publishTask?.cancel()
        publishTask = nil
        pendingText = nil
        pendingThinking = nil
        playback?.clear()
    }

    private func startPublishLoop() {
        guard publishTask == nil else { return }
        publishTask = Task { @MainActor [weak self] in
            while let self {
                let text = self.pendingText
                let thinking = self.pendingThinking
                guard text != nil || thinking != nil else { break }
                self.pendingText = nil
                self.pendingThinking = nil
                if let text { self.playback?.apply(text) }
                if let thinking { self.playback?.applyThinking(thinking) }
                try? await Task.sleep(for: .milliseconds(33))
                if Task.isCancelled { break }
            }
            self?.publishTask = nil
        }
    }
}
