//
//  guardian_assessment.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/guardian_assessment.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Status / outcome / risk mapping is faithful. Emit is os.Logger.
//

import CodexProtocol
import CodexUtils

private let maxRationaleBytes = 65_536

extension SessionTelemetry {
    /// Record one terminal review after the host checks the opt-in.
    public func guardianAssessment(
        _ assessment: GuardianAssessmentEvent,
        outcome: GuardianAssessmentOutcome?
    ) {
        let status: String
        switch assessment.status {
        case .inProgress:
            return
        case .approved:
            status = "approved"
        case .denied:
            status = "denied"
        case .timedOut:
            status = "timed_out"
        case .aborted:
            status = "aborted"
        }
        var fields: [String: String] = [
            "event.name": "codex.guardian_assessment",
            "review.id": assessment.id,
            "turn.id": assessment.turnId,
            "status": status,
            "started_at_ms": String(assessment.startedAtMs),
        ]
        if let itemId = assessment.targetItemId {
            fields["item.id"] = itemId
        }
        if let outcome {
            fields["outcome"] = outcome.rawValue
        }
        if let risk = assessment.riskLevel {
            fields["risk_level"] = risk.rawValue
        }
        if let authorization = assessment.userAuthorization {
            fields["user_authorization"] = authorization.rawValue
        }
        if let completed = assessment.completedAtMs {
            fields["completed_at_ms"] = String(completed)
        }
        if let rationale = assessment.rationale {
            let clipped = String(takeBytesAtCharBoundary(rationale, maxb: maxRationaleBytes))
            fields["rationale"] = clipped
            fields["rationale_length"] = String(rationale.utf8.count)
            fields["rationale_truncated"] = String(rationale.utf8.count > maxRationaleBytes)
        }
        logOtelEvent(self, fields)
    }
}
