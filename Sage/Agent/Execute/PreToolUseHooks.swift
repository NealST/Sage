//
//  PreToolUseHooks.swift
//  Sage
//
//  Declarative, read-only hook rules loaded from project and activated skills.
//

import Foundation

nonisolated enum PreToolUseDecision: Sendable, Equatable {
    case allow
    case ask(String)
    case deny(String)
}

nonisolated struct PreToolUseHookRule: Codable, Sendable, Equatable {
    enum Action: String, Codable, Sendable {
        case allow
        case ask
        case deny
    }

    var tool: String
    var action: Action
    var argumentEquals: [String: String]?
    var argumentContains: [String: String]?
    var reason: String?

    private enum CodingKeys: String, CodingKey {
        case tool, action, reason
        case argumentEquals = "argument_equals"
        case argumentContains = "argument_contains"
    }
}

nonisolated struct PreToolUseHookConfig: Codable, Sendable, Equatable {
    var preToolUse: [PreToolUseHookRule]

    private enum CodingKeys: String, CodingKey {
        case preToolUse = "pre_tool_use"
    }
}

actor PreToolUseHookEvaluator {
    static let shared = PreToolUseHookEvaluator()

    private struct CachedFile {
        var modificationDate: Date?
        var size: UInt64?
        var result: Result<[PreToolUseHookRule], HookLoadError>
    }

    private struct HookLoadError: Error, Sendable {
        var message: String
    }

    private var cache: [URL: CachedFile] = [:]

    func evaluate(
        toolName: String,
        argumentsJSON: String,
        projectRoot: URL?,
        activatedSkills: [SkillRecord]
    ) -> PreToolUseDecision {
        let urls = hookURLs(projectRoot: projectRoot, activatedSkills: activatedSkills)
        var matching: [(rule: PreToolUseHookRule, source: URL)] = []

        for url in urls {
            switch rules(at: url) {
            case .success(let rules):
                matching.append(contentsOf: rules.compactMap { rule in
                    rule.matches(toolName: toolName, argumentsJSON: argumentsJSON)
                        ? (rule, url)
                        : nil
                })
            case .failure(let error):
                return .deny(error.message)
            }
        }

        if let denied = matching.first(where: { $0.rule.action == .deny }) {
            return .deny(message(for: denied.rule, source: denied.source))
        }
        if let asked = matching.first(where: { $0.rule.action == .ask }) {
            return .ask(message(for: asked.rule, source: asked.source))
        }
        return .allow
    }

    private func hookURLs(
        projectRoot: URL?,
        activatedSkills: [SkillRecord]
    ) -> [URL] {
        var urls: [URL] = []
        if let projectRoot {
            urls.append(
                projectRoot
                    .appendingPathComponent(".sage", isDirectory: true)
                    .appendingPathComponent("hooks.json")
            )
        }
        urls.append(contentsOf: activatedSkills.map {
            URL(fileURLWithPath: $0.path)
                .deletingLastPathComponent()
                .appendingPathComponent("hooks.json")
        })
        return Array(Set(urls.map(\.standardizedFileURL)))
            .sorted { $0.path < $1.path }
    }

    private func rules(
        at url: URL
    ) -> Result<[PreToolUseHookRule], HookLoadError> {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes != nil else {
            cache.removeValue(forKey: url)
            return .success([])
        }

        let modificationDate = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.uint64Value
        if let cached = cache[url],
           cached.modificationDate == modificationDate,
           cached.size == size {
            return cached.result
        }

        let result: Result<[PreToolUseHookRule], HookLoadError>
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(PreToolUseHookConfig.self, from: data)
            result = .success(config.preToolUse)
        } catch {
            result = .failure(
                HookLoadError(
                    message: "Invalid PreToolUse hook config at \(url.path): \(error.localizedDescription)"
                )
            )
        }
        cache[url] = CachedFile(
            modificationDate: modificationDate,
            size: size,
            result: result
        )
        return result
    }

    private func message(for rule: PreToolUseHookRule, source: URL) -> String {
        let reason = rule.reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "Matched PreToolUse rule '\(rule.tool)'."
        return "\(reason) [\(source.lastPathComponent)]"
    }
}

private extension PreToolUseHookRule {
    nonisolated func matches(toolName: String, argumentsJSON: String) -> Bool {
        guard wildcardMatch(pattern: tool, value: toolName) else { return false }
        guard argumentEquals != nil || argumentContains != nil else { return true }
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        if let argumentEquals {
            for (key, expected) in argumentEquals {
                guard stringValue(object[key]) == expected else { return false }
            }
        }
        if let argumentContains {
            for (key, expected) in argumentContains {
                guard stringValue(object[key])?.contains(expected) == true else { return false }
            }
        }
        return true
    }

    nonisolated private func wildcardMatch(pattern: String, value: String) -> Bool {
        var expression = NSRegularExpression.escapedPattern(for: pattern)
        expression = expression.replacingOccurrences(of: "\\*", with: ".*")
        guard let regex = try? NSRegularExpression(pattern: "^\(expression)$") else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    nonisolated private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
