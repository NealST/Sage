import Foundation

/// Coalesces SSE token updates to ~30 Hz before writing `StreamingPlayback`.
@MainActor
final class StreamingTextPump {
    private weak var playback: StreamingPlayback?
    private var pendingText: String?
    private var publishTask: Task<Void, Never>?

    func attach(playback: StreamingPlayback) {
        self.playback = playback
    }

    func publish(_ text: String) {
        pendingText = text
        guard publishTask == nil else { return }
        publishTask = Task { @MainActor [weak self] in
            while let self, let pending = self.pendingText {
                self.pendingText = nil
                self.playback?.apply(pending)
                try? await Task.sleep(for: .milliseconds(33))
                if Task.isCancelled { break }
            }
            self?.publishTask = nil
        }
    }

    func flush(_ text: String) {
        publishTask?.cancel()
        publishTask = nil
        pendingText = nil
        playback?.apply(text)
    }

    func clear() {
        publishTask?.cancel()
        publishTask = nil
        pendingText = nil
        playback?.clear()
    }
}
