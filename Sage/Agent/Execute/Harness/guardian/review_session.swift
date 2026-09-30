//
//  review_session.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/review_session.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Isolated completion plus Codex attempt budget. Production uses
//  `GuardianReviewerConfig` for the review-role model and contract.
//  Parse failures retry up to `maxReviewAttempts`. Tests can replace
//  `complete`.
//

import Foundation

struct GuardianReviewSessionLimits: Equatable, Sendable {
    var maxAttempts: Int
    var timeout: Duration

    static let standard = GuardianReviewSessionLimits(
        maxAttempts: GuardianReviewSession.maxReviewAttempts,
        timeout: GuardianReviewSession.reviewTimeout
    )
}

@MainActor
final class GuardianReviewSession {
    static let shared = GuardianReviewSession()
    /// Codex `MAX_REVIEW_ATTEMPTS`.
    static let maxReviewAttempts = 3
    /// Codex `REVIEW_TIMEOUT`.
    static let reviewTimeout: Duration = .seconds(90)

    /// Test seam. Production talks to the review-role model.
    var complete: ((String) async throws -> String)?

    func review(
        prompt: String,
        config: GuardianReviewerConfig? = nil,
        limits: GuardianReviewSessionLimits = .standard
    ) async throws -> String {
        let resolved = config ?? GuardianReviewerConfig.resolveLive()
        let attempts = max(limits.maxAttempts, 1)
        var lastUnparsed = ""
        var lastError: Error?
        for attempt in 1...attempts {
            if Task.isCancelled { throw GuardianReviewError.cancelled }
            do {
                let raw = try await reviewOnce(
                    prompt: prompt,
                    config: resolved,
                    timeout: limits.timeout
                )
                if GuardianPrompt.parse(raw) != nil || GuardianPrompt.isAsk(raw) {
                    return raw
                }
                lastUnparsed = raw
            } catch is CancellationError {
                throw GuardianReviewError.cancelled
            } catch GuardianReviewError.cancelled {
                throw GuardianReviewError.cancelled
            } catch GuardianReviewError.notConfigured {
                throw GuardianReviewError.notConfigured
            } catch {
                lastError = error
                if attempt == attempts { throw error }
                continue
            }
            if attempt == attempts { break }
        }
        if !lastUnparsed.isEmpty { return lastUnparsed }
        throw lastError ?? GuardianReviewError.notConfigured
    }

    private func reviewOnce(
        prompt: String,
        config: GuardianReviewerConfig,
        timeout: Duration
    ) async throws -> String {
        if let complete {
            return try await complete(prompt)
        }
        guard !config.settings.apiKey.isEmpty else {
            throw GuardianReviewError.notConfigured
        }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let turn = try await ModelClient().complete(
                    events: [
                        AgentEvent(kind: .systemInstruction, content: config.instructions),
                        AgentEvent(kind: .userInput, content: prompt),
                    ],
                    tools: [],
                    settings: config.settings,
                    toolChoice: "none",
                    temperature: 0
                )
                return turn.content ?? ""
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw GuardianReviewError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

enum GuardianReviewError: Error, Equatable {
    case notConfigured
    case timeout
    case cancelled
}
