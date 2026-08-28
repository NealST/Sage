//
//  SkillSecretStore.swift
//  Sage
//
//  Skill-scoped secret injection backed by Keychain.
//

import Foundation

nonisolated enum SkillSecretStore {
    static func isValidEnvironmentName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    static func environment(for skill: SkillRecord) throws -> [String: String] {
        var environment: [String: String] = [:]
        var missing: [String] = []
        let parent = ProcessInfo.processInfo.environment

        for name in skill.requiredSecretNames {
            let account = accountName(skillID: skill.id, variable: name)
            if let stored = KeychainStore.get(account: account) {
                environment[name] = stored
            } else if let inherited = parent[name], !inherited.isEmpty {
                try KeychainStore.set(inherited, account: account)
                environment[name] = inherited
            } else {
                missing.append(name)
            }
        }

        guard missing.isEmpty else {
            throw ToolError.operationFailed(
                """
                Skill '\(skill.name)' requires missing secret variables: \
                \(missing.joined(separator: ", ")). Configure them before running this skill.
                """
            )
        }
        return environment
    }

    private static func accountName(skillID: String, variable: String) -> String {
        "skill-secret|\(skillID)|\(variable)"
    }
}
