//
//  ToolArgumentValidator.swift
//  Sage
//
//  Lightweight JSON Schema validation for model-produced tool arguments.
//

import Foundation

nonisolated enum ToolArgumentValidator {
    static func validate(argumentsJSON: String, against schema: JSONValue) throws {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "{}" : trimmed
        guard let data = normalized.data(using: .utf8) else {
            throw ToolError.invalidArguments("Arguments are not valid UTF-8 JSON.")
        }

        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ToolError.invalidArguments("Arguments must be valid JSON: \(error.localizedDescription)")
        }

        try validate(value, against: schema, path: "arguments")
    }

    private static func validate(
        _ value: JSONValue,
        against schema: JSONValue,
        path: String
    ) throws {
        guard case .object(let rules) = schema else { return }
        try validateConstAndEnum(value, rules: rules, path: path)
        try validateType(value, rules: rules, path: path)
        try validateCombinators(value, rules: rules, path: path)
        try validateObject(value, rules: rules, path: path)
        try validateArray(value, rules: rules, path: path)
    }

    private static func validateConstAndEnum(
        _ value: JSONValue,
        rules: [String: JSONValue],
        path: String
    ) throws {
        if let constant = rules["const"], constant != value {
            throw ToolError.invalidArguments("\(path) must equal \(constant.displayValue).")
        }
        if let allowed = rules["enum"]?.arrayValue, !allowed.contains(value) {
            let choices = allowed.map(\.displayValue).joined(separator: ", ")
            throw ToolError.invalidArguments("\(path) must be one of: \(choices).")
        }
    }

    private static func validateType(
        _ value: JSONValue,
        rules: [String: JSONValue],
        path: String
    ) throws {
        if let expectedTypes = schemaTypes(from: rules["type"]),
           !expectedTypes.isEmpty,
           !expectedTypes.contains(where: { matches(value, type: $0) }) {
            throw ToolError.invalidArguments(
                "\(path) must be \(expectedTypes.joined(separator: " or ")); got \(value.typeName)."
            )
        }
    }

    private static func validateCombinators(
        _ value: JSONValue,
        rules: [String: JSONValue],
        path: String
    ) throws {
        if let schemas = rules["allOf"]?.arrayValue {
            for childSchema in schemas {
                try validate(value, against: childSchema, path: path)
            }
        }
        if let schemas = rules["anyOf"]?.arrayValue,
           !schemas.contains(where: { (try? validate(value, against: $0, path: path)) != nil }) {
            throw ToolError.invalidArguments("\(path) does not match any allowed schema.")
        }
        if let schemas = rules["oneOf"]?.arrayValue {
            let matchCount = schemas.reduce(into: 0) { count, childSchema in
                if (try? validate(value, against: childSchema, path: path)) != nil {
                    count += 1
                }
            }
            if matchCount != 1 {
                throw ToolError.invalidArguments("\(path) must match exactly one allowed schema.")
            }
        }
    }

    private static func validateObject(
        _ value: JSONValue,
        rules: [String: JSONValue],
        path: String
    ) throws {
        guard case .object(let object) = value else { return }
        let required = rules["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let missing = required.filter { object[$0] == nil }
        if !missing.isEmpty {
            throw ToolError.invalidArguments(
                """
                \(path) is missing required field\(missing.count == 1 ? "" : "s"): \
                \(missing.joined(separator: ", ")).
                """
            )
        }
        guard case .object(let properties) = rules["properties"] else { return }
        if rules["additionalProperties"] == .bool(false) {
            let unknown = object.keys.filter { properties[$0] == nil }.sorted()
            if !unknown.isEmpty {
                throw ToolError.invalidArguments(
                    """
                    \(path) contains unknown field\(unknown.count == 1 ? "" : "s"): \
                    \(unknown.joined(separator: ", ")).
                    """
                )
            }
        }
        for (name, childSchema) in properties {
            guard let child = object[name] else { continue }
            try validate(child, against: childSchema, path: "\(path).\(name)")
        }
    }

    private static func validateArray(
        _ value: JSONValue,
        rules: [String: JSONValue],
        path: String
    ) throws {
        guard case .array(let items) = value, let itemSchema = rules["items"] else { return }
        for (index, item) in items.enumerated() {
            try validate(item, against: itemSchema, path: "\(path)[\(index)]")
        }
    }

    private static func schemaTypes(from value: JSONValue?) -> [String]? {
        switch value {
        case .string(let type):
            return [type]

        case .array(let values):
            return values.compactMap(\.stringValue)

        case nil:
            return nil

        default:
            return []
        }
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string),
             ("number", .number), ("boolean", .bool), ("null", .null):
            return true

        case ("integer", .number(let number)):
            return number.isFinite && number.rounded(.towardZero) == number

        default:
            return false
        }
    }
}

private extension JSONValue {
    nonisolated var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    nonisolated var typeName: String {
        switch self {
        case .string: return "string"

        case .number(let value):
            return value.isFinite && value.rounded(.towardZero) == value ? "integer" : "number"
        case .bool: return "boolean"
        case .object: return "object"
        case .array: return "array"
        case .null: return "null"
        }
    }

    nonisolated var displayValue: String {
        switch self {
        case .string(let value): return "'\(value)'"
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return "null"

        case .object, .array:
            return (try? JSONEncoder().encode(self))
                .flatMap { String(data: $0, encoding: .utf8) } ?? typeName
        }
    }
}
