//
//  SkillExtractionParsing.swift
//  Sage
//
//  JSON parse helpers for skill extraction / compose responses.
//

import Foundation

nonisolated enum SkillExtractionParsing {

    // MARK: - Response Parsing

    /// Normalizes a model-generated skill name to valid kebab-case.
    /// Converts spaces/underscores to hyphens, lowercases, strips invalid chars.
    static func normalizeSkillName(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var collapsed: [Character] = []
        for char in lowered {
            let mapped: Character
            if char.isASCII && (char.isLowercase || char.isNumber) {
                mapped = char
            } else if char == "-" || char == "_" || char == " " {
                mapped = "-"
            } else {
                continue
            }
            if mapped == "-" && collapsed.last == "-" { continue }
            collapsed.append(mapped)
        }

        while collapsed.first == "-" { collapsed.removeFirst() }
        while collapsed.last == "-" { collapsed.removeLast() }

        let name = String(collapsed)
        return name.count <= 64 ? name : String(name.prefix(64))
    }

    static func parseComposeResponse(_ content: String) throws -> SkillDraft {
        guard let parsed = ModelJSONSlice.jsonObject(in: content),
              let description = parsed["description"] as? String,
              let body = parsed["body"] as? String else {
            throw SkillCompositionError.invalidResponse
        }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty, !trimmedBody.isEmpty else {
            throw SkillCompositionError.invalidResponse
        }
        guard trimmedDescription.count <= 1024 else {
            throw SkillCompositionError.invalidResponse
        }

        return SkillDraft(description: trimmedDescription, body: trimmedBody)
    }

    enum ExtractionAction: String {
        case skip
        case new
        case enhance
    }

    static func parseResponse(_ content: String) -> SkillExtractionResult {
        guard let parsed = ModelJSONSlice.jsonObject(in: content),
              let rawAction = parsed["action"] as? String,
              let action = ExtractionAction(rawValue: rawAction) else {
            return .skip
        }

        switch action {
        case .new:
            guard let rawName = parsed["name"] as? String,
                  let description = parsed["description"] as? String else {
                return .skip
            }
            let name = normalizeSkillName(rawName)
            guard !name.isEmpty else { return .skip }
            return .newSkill(name: name, description: description)

        case .enhance:
            guard let target = parsed["target"] as? String,
                  let description = parsed["description"] as? String else {
                return .skip
            }
            let normalizedTarget = normalizeSkillName(target)
            guard !normalizedTarget.isEmpty else { return .skip }
            return .enhance(existingName: normalizedTarget, description: description)

        case .skip:
            return .skip
        }
    }

    /// Coerces analyze output toward enhance when the catalog / preferred neighbors make `new` redundant.
    ///
    /// - Exact catalog name collision → enhance
    /// - Single preferred neighbor + `new` → enhance that neighbor (cross-task aggregation)
    /// - `enhance` with unknown target → remap via catalog / preferred list when possible
    static func reconcile(
        _ result: SkillExtractionResult,
        catalogNames: Set<String>,
        preferredTargets: [String]
    ) -> SkillExtractionResult {
        let preferredInCatalog = preferredTargets.filter { catalogNames.contains($0) }

        switch result {
        case .skip:
            return .skip

        case .newSkill(let name, let description):
            if catalogNames.contains(name) {
                return .enhance(existingName: name, description: description)
            }
            if preferredInCatalog.count == 1, let only = preferredInCatalog.first {
                return .enhance(existingName: only, description: description)
            }
            return .newSkill(name: name, description: description)

        case .enhance(let target, let description):
            if catalogNames.contains(target) {
                return .enhance(existingName: target, description: description)
            }
            if let match = catalogNames.first(where: {
                $0.caseInsensitiveCompare(target) == .orderedSame
            }) {
                return .enhance(existingName: match, description: description)
            }
            if preferredInCatalog.contains(target) {
                return .enhance(existingName: target, description: description)
            }
            if preferredInCatalog.count == 1, let only = preferredInCatalog.first {
                return .enhance(existingName: only, description: description)
            }
            if let first = preferredInCatalog.first {
                return .enhance(existingName: first, description: description)
            }
            return .skip
        }
    }
}
