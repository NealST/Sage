//
//  catalog_parameters.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/catalog_parameters.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

func parseCatalogParameters(_ parameters: String) throws -> JsonSchema {
    guard let data = parameters.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["type"] as? String == "object" else {
        throw CatalogParameterError.notObject
    }
    do {
        return try JSONDecoder().decode(JsonSchema.self, from: data)
    } catch {
        throw CatalogParameterError.unsupported
    }
}

enum CatalogParameterError: Error, Equatable {
    case notObject
    case unsupported

    var message: String {
        switch self {
        case .notObject:
            return "schema must declare an object type"
        case .unsupported:
            return "schema uses unsupported JSON Schema structures"
        }
    }
}
