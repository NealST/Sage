//
//  retained_context.swift
//  Sage
//
//  Port of codex-rs/core/src/session/retained_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A verified `request_user_input` answer is recorded when the turn has
//  `guardian_approval` enabled and history is thread-owned. Blank answers
//  and unknown question ids are skipped. A new record is appended as
//  `RolloutItem::RetainedContext` when rollout persistence is enabled.
//

import CodexCore
import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

extension Session {
    func retainedContextSummary() -> String? {
        nil
    }

    /// Opens a rollout writer under `codexHome`. Later verified answers append
    /// to that file. Sessions that never call this keep the answer in memory.
    func enableRolloutPersistence() {
        services.persistRolloutItems = { [weak self] items in
            guard let self else { return }
            try await self.appendOwnedRolloutItems(items)
        }
    }

    /// rust `Session::record_retained_context` for `VerifiedAnswer`.
    func recordRetainedVerifiedAnswer(
        turnContext: TurnContext,
        callId: String,
        questions: [RequestUserInputQuestion],
        response: RequestUserInputResponse,
        acceptanceOrder: UInt64?
    ) async {
        guard turnContext.config.features.enabled(.guardianApproval),
              state.history.guardianReviewMode == .threadOwned,
              let acceptanceOrder
        else { return }
        let recorded = retainedVerifiedQuestions(questions: questions, response: response)
        guard !recorded.isEmpty else { return }
        guard let stored = state.history.recordVerifiedAnswer(
            RetainedVerifiedAnswer(
                turnId: turnContext.subId,
                callId: callId,
                questions: recorded,
                acceptanceOrder: acceptanceOrder
            )
        ) else { return }
        _ = await persistRolloutItems([verifiedAnswerRolloutItem(stored)])
    }

    /// rust `persist_rollout_items`. No writer means nothing is written.
    func persistRolloutItems(_ items: [RolloutItem]) async -> Bool {
        guard let persist = services.persistRolloutItems else { return true }
        do {
            try await persist(items)
            return true
        } catch {
            return false
        }
    }

    /// Replays verified answers and response items from an existing rollout.
    /// Does not append another copy of those items.
    func restoreVerifiedAnswers(
        fromRolloutPath path: String,
        truncationPolicy: TruncationPolicy = .bytes(10_000)
    ) {
        guard let items = try? RolloutRecorder.loadRolloutItems(path: path).items else { return }
        RolloutReconstruction.restoreVerifiedAnswers(
            from: items, into: state.history, truncationPolicy: truncationPolicy)
        if let settings = state.history.reconstructedTurnSettings {
            state.setPreviousTurnSettings(PreviousTurnSettings(
                model: settings.model,
                compHash: settings.compHash,
                realtimeActive: settings.realtimeActive ?? false
            ))
        } else {
            state.setPreviousTurnSettings(nil)
        }
    }

    /// Keep appending to a rollout that already exists.
    func resumeRolloutPersistence(path: String) {
        rolloutLock.lock()
        if rolloutRecorder == nil {
            rolloutRecorder = try? RolloutRecorder.create(
                config: RolloutConfig(codexHome: state.sessionConfiguration.codexHome),
                params: .resume(path: path)
            )
        }
        rolloutLock.unlock()
        enableRolloutPersistence()
    }

    func persistedRolloutPath() -> String? {
        rolloutLock.lock()
        defer { rolloutLock.unlock() }
        return rolloutRecorder?.rolloutPath
    }

    func appendOwnedRolloutItems(_ items: [RolloutItem]) throws {
        rolloutLock.lock()
        if rolloutRecorder == nil {
            do {
                rolloutRecorder = try RolloutRecorder.create(
                    config: RolloutConfig(codexHome: state.sessionConfiguration.codexHome),
                    params: .new(
                        conversationId: threadId,
                        source: state.sessionConfiguration.sessionSource,
                        originator: "sage"
                    )
                )
            } catch {
                rolloutLock.unlock()
                throw error
            }
        }
        let recorder = rolloutRecorder
        rolloutLock.unlock()
        try recorder?.recordItems(items)
        try recorder?.flush()
    }
}

func verifiedAnswerRolloutItem(_ answer: RetainedVerifiedAnswer) -> RolloutItem {
    let questions = answer.questions.map { question in
        CodexProtocol.JSONValue.object([
            "question": .string(question.question),
            "answer": .string(question.answer),
        ])
    }
    return .retainedContext(.object([
        "type": .string("verified_answer"),
        "turn_id": .string(answer.turnId),
        "call_id": .string(answer.callId),
        "questions": .array(questions),
        "acceptance_order": .uint(answer.acceptanceOrder),
    ]))
}

func verifiedAnswer(from item: RolloutItem) -> RetainedVerifiedAnswer? {
    guard case .retainedContext(let payload) = item,
          let object = payload.objectValue,
          object["type"]?.stringValue == "verified_answer",
          let turnId = object["turn_id"]?.stringValue,
          let callId = object["call_id"]?.stringValue
    else { return nil }
    var questions: [RetainedVerifiedQuestion] = []
    for value in object["questions"]?.arrayValue ?? [] {
        guard let fields = value.objectValue,
              let question = fields["question"]?.stringValue,
              let answer = fields["answer"]?.stringValue
        else { continue }
        questions.append(RetainedVerifiedQuestion(question: question, answer: answer))
    }
    let order = UInt64(exactly: object["acceptance_order"]?.intValue ?? 0) ?? 0
    return RetainedVerifiedAnswer(
        turnId: turnId,
        callId: callId,
        questions: questions,
        acceptanceOrder: order
    )
}

func retainedVerifiedQuestions(
    questions: [RequestUserInputQuestion],
    response: RequestUserInputResponse
) -> [RetainedVerifiedQuestion] {
    var recorded: [RetainedVerifiedQuestion] = []
    for question in questions {
        guard let answer = response.answers[question.id] else { continue }
        let answers = answer.answers.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if answers.isEmpty { continue }
        var questionText = question.question
        for option in question.options ?? [] where answer.answers.contains(option.label) {
            questionText += "\n\(option.label): \(option.description)"
        }
        recorded.append(
            RetainedVerifiedQuestion(question: questionText, answer: answers.joined(separator: "\n"))
        )
    }
    return recorded
}
