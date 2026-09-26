//
//  json_schema.swift
//  Sage
//
//  Port of codex-rs/tools/src/json_schema/types.rs constructors used by
//  core/src/tools (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The tools crate is not a separate Swift module. This is the schema
//  subset handlers and catalog_parameters need.
//

import CodexProtocol
import Foundation

typealias HarnessJSON = CodexProtocol.JSONValue

enum JsonSchemaPrimitiveType: String, Codable, Equatable, Sendable {
    case string, number, boolean, integer, object, array, null
}

enum JsonSchemaType: Equatable, Sendable {
    case single(JsonSchemaPrimitiveType)
    case multiple([JsonSchemaPrimitiveType])
}

indirect enum AdditionalProperties: Equatable, Sendable {
    case boolean(Bool)
    case schema(JsonSchema)
}

struct JsonSchema: Equatable, Sendable {
    var schemaType: JsonSchemaType?
    var description: String?
    var enumValues: [HarnessJSON]?
    var items: BoxSchema?
    var properties: [String: JsonSchema]?
    var required: [String]?
    var additionalProperties: AdditionalProperties?
    var minItems: Int?

    final class BoxSchema: Equatable, Sendable {
        var value: JsonSchema
        init(value: JsonSchema) { self.value = value }
        static func == (lhs: BoxSchema, rhs: BoxSchema) -> Bool { lhs.value == rhs.value }
    }

    static func typed(_ type: JsonSchemaPrimitiveType, description: String? = nil) -> JsonSchema {
        JsonSchema(schemaType: .single(type), description: description)
    }

    static func boolean(_ description: String? = nil) -> JsonSchema {
        typed(.boolean, description: description)
    }

    static func string(_ description: String? = nil) -> JsonSchema {
        typed(.string, description: description)
    }

    static func number(_ description: String? = nil) -> JsonSchema {
        typed(.number, description: description)
    }

    static func integer(_ description: String? = nil) -> JsonSchema {
        typed(.integer, description: description)
    }

    static func stringEnum(_ values: [String], description: String? = nil) -> JsonSchema {
        JsonSchema(
            schemaType: .single(.string),
            description: description,
            enumValues: values.map { .string($0) }
        )
    }

    static func array(_ items: JsonSchema, description: String? = nil) -> JsonSchema {
        JsonSchema(
            schemaType: .single(.array),
            description: description,
            items: BoxSchema(value: items)
        )
    }

    static func object(
        _ properties: [String: JsonSchema],
        required: [String]? = nil,
        additionalProperties: Bool? = nil
    ) -> JsonSchema {
        JsonSchema(
            schemaType: .single(.object),
            properties: properties,
            required: required,
            additionalProperties: additionalProperties.map { .boolean($0) }
        )
    }
}

extension JsonSchema: Codable {
    enum CodingKeys: String, CodingKey {
        case type_ = "type"
        case description
        case enumValues = "enum"
        case items, properties, required
        case additionalProperties
        case minItems
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try container.decodeIfPresent(String.self, forKey: .type_),
           let primitive = JsonSchemaPrimitiveType(rawValue: raw) {
            schemaType = .single(primitive)
        } else if let raw = try container.decodeIfPresent([String].self, forKey: .type_) {
            schemaType = .multiple(raw.compactMap(JsonSchemaPrimitiveType.init(rawValue:)))
        } else {
            schemaType = nil
        }
        description = try container.decodeIfPresent(String.self, forKey: .description)
        enumValues = try container.decodeIfPresent([HarnessJSON].self, forKey: .enumValues)
        if let nested = try container.decodeIfPresent(JsonSchema.self, forKey: .items) {
            items = BoxSchema(value: nested)
        }
        properties = try container.decodeIfPresent([String: JsonSchema].self, forKey: .properties)
        required = try container.decodeIfPresent([String].self, forKey: .required)
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .additionalProperties) {
            additionalProperties = .boolean(flag)
        } else if let nested = try container.decodeIfPresent(JsonSchema.self, forKey: .additionalProperties) {
            additionalProperties = .schema(nested)
        } else {
            additionalProperties = nil
        }
        minItems = try container.decodeIfPresent(Int.self, forKey: .minItems)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch schemaType {
        case .single(let type):
            try container.encode(type.rawValue, forKey: .type_)
        case .multiple(let types):
            try container.encode(types.map(\.rawValue), forKey: .type_)
        case nil:
            break
        }
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
        try container.encodeIfPresent(items?.value, forKey: .items)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        switch additionalProperties {
        case .boolean(let flag):
            try container.encode(flag, forKey: .additionalProperties)
        case .schema(let schema):
            try container.encode(schema, forKey: .additionalProperties)
        case nil:
            break
        }
        try container.encodeIfPresent(minItems, forKey: .minItems)
    }
}
