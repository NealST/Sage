//
//  json.swift
//  CodexUtils
//
//  Port of codex-rs/core/src/utils/json.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Counts serialized JSON bytes without retaining the serialized output.
//  Upstream streams through a byte-counting `io::Write`; Swift's `JSONEncoder`
//  always materializes `Data`, so this counts the encoded data's length. Byte
//  counts match serde_json for the same value as long as key order does not
//  affect length (it never does). core's own module does not exist yet, so
//  this file compiles into CodexUtils and is `public` rather than
//  `pub(crate)` (plan §4.1 transitional note).
//

import Foundation

/// `serialized_json_bytes` — counts serialized JSON bytes without retaining
/// the serialized output.
public func serializedJSONBytes<T: Encodable>(_ value: T) throws -> Int {
    try JSONEncoder().encode(value).count
}
