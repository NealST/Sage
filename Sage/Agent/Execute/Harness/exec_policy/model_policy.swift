//
//  model_policy.swift
//  Sage
//
//  Port of codex-rs/core/src/exec_policy/model_policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexExecPolicy

enum AllowPrefixRules: Equatable, Sendable {
    case honor
    case ignoreForCyberModel
}

extension ExecPolicyManager {
    func currentForEnvironment(
        _ environmentPolicy: ExecPolicyRequirements?,
        _ allowPrefixRules: AllowPrefixRules
    ) -> Policy {
        let policy = currentForPrefixRules(allowPrefixRules)
        if let environmentPolicy {
            return policy.mergeOverlay(environmentPolicy.policy)
        }
        return policy
    }

    func currentForPrefixRules(_ allowPrefixRules: AllowPrefixRules) -> Policy {
        let policy = current()
        if allowPrefixRules == .honor {
            return policy
        }

        var filtered: [String: [any ExecPolicyRule]] = [:]
        for (program, rules) in policy.rules() {
            let kept = rules.filter { rule in
                if let prefix = rule as? PrefixRule, prefix.decision == .allow {
                    return false
                }
                return true
            }
            if !kept.isEmpty {
                filtered[program] = kept
            }
        }
        return Policy.fromParts(
            rulesByProgram: filtered,
            networkRules: policy.networkRulesList(),
            hostExecutablesByName: policy.hostExecutables()
        )
    }
}
