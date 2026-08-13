import Foundation

/// Whether a user utterance is a single intent or several packed together.
enum IntentComplexity: Sendable {
    case simple
    case complex
}

/// Classifies user messages as simple vs multi-intent using the on-device model.
actor IntentComplexityClassifier {
    private let modelService: LocalModelService

    init(modelService: LocalModelService = .shared) {
        self.modelService = modelService
    }

    /// Returns `.simple` when the model is unavailable or parsing fails (fail open).
    /// Skips the local generation when the utterance clearly looks like a single intent.
    func classify(_ userMessage: String) async -> IntentComplexity {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .simple }

        // Fast path: no multi-intent cues → skip a local model round-trip.
        guard Self.shouldRunModelClassifier(for: trimmed) else { return .simple }

        guard await modelService.isReady else { return .simple }

        let system = """
        You classify whether a user request contains one intent or multiple distinct intents.

        Rules:
        - Output ONLY JSON: {"complexity":"simple"} or {"complexity":"complex"}
        - simple: one goal / one primary ask (even if it has details or constraints)
        - complex: two or more separable goals that would be better done as ordered steps \
          (e.g. "rebase then run tests then open a PR", "translate this and also summarize it")
        - Lists of requirements for ONE deliverable are still simple
        - When unsure, choose simple
        """

        let user = """
        User message:
        \(String(trimmed.prefix(800)))
        """

        do {
            let output = try await modelService.generate(
                systemPrompt: system,
                userPrompt: user,
                maxTokens: 24,
                temperature: 0
            )
            return Self.parse(output)
        } catch {
            return .simple
        }
    }

    /// Heuristic gate before spending a local-model call on complexity.
    nonisolated static func shouldRunModelClassifier(for message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // Very short asks are almost always one intent.
        if trimmed.count < 48 { return false }

        let lower = trimmed.lowercased()
        let cues = [
            " then ", " and then ", " after that ", " afterwards ",
            " also ", " as well as ", " plus ",
            "然后", "并且", "接着", "同时", "另外", "以及", "再帮", "再把",
            "；",
        ]
        if cues.contains(where: { lower.contains($0) }) { return true }
        if trimmed.contains("\n") { return true }
        // Numbered / bulleted multi-step lists.
        if lower.contains("\n- ") || lower.contains("\n* ") { return true }
        if lower.range(of: #"\n\d+[\.\)]\s"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func parse(_ output: String) -> IntentComplexity {
        guard let obj = ModelJSONSlice.jsonObject(in: output),
              let raw = obj["complexity"] as? String else {
            return .simple
        }
        return raw.lowercased() == "complex" ? .complex : .simple
    }
}
