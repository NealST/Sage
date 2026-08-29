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

    static func hasStoredSecret(_ variable: String, for skill: SkillRecord) -> Bool {
        KeychainStore.get(account: accountName(skillID: skill.id, variable: variable)) != nil
    }

    static func setSecret(_ value: String, variable: String, for skill: SkillRecord) throws {
        guard skill.requiredSecretNames.contains(variable),
              isValidEnvironmentName(variable),
              !value.isEmpty else {
            throw ToolError.invalidArguments("Invalid or empty Skill secret.")
        }
        try KeychainStore.set(
            value,
            account: accountName(skillID: skill.id, variable: variable)
        )
    }

    static func removeSecret(_ variable: String, for skill: SkillRecord) {
        KeychainStore.delete(account: accountName(skillID: skill.id, variable: variable))
    }

    static func removeAllSecrets(for skill: SkillRecord) {
        KeychainStore.deleteAccounts(withPrefix: accountPrefix(skillID: skill.id))
    }

    static func removeAllSecrets() {
        KeychainStore.deleteAccounts(withPrefix: "skill-secret|")
    }

    private static func accountName(skillID: String, variable: String) -> String {
        accountPrefix(skillID: skillID) + variable
    }

    private static func accountPrefix(skillID: String) -> String {
        "skill-secret|\(skillID)|"
    }
}
