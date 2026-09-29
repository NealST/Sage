//
//  validation.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/validation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

func validateTags(_ tags: [String: String]) throws {
    for (key, value) in tags {
        try validateTagKey(key)
        try validateTagValue(value)
    }
}

func validateMetricName(_ name: String) throws {
    if name.isEmpty {
        throw MetricsError.emptyMetricName
    }
    if !name.allSatisfy(isMetricChar) {
        throw MetricsError.invalidMetricName(name: name)
    }
}

func validateTagKey(_ key: String) throws {
    try validateTagComponent(key, label: "tag key")
}

func validateTagValue(_ value: String) throws {
    try validateTagComponent(value, label: "tag value")
}

private func validateTagComponent(_ value: String, label: String) throws {
    if value.isEmpty {
        throw MetricsError.emptyTagComponent(label: label)
    }
    if !value.allSatisfy(isTagChar) {
        throw MetricsError.invalidTagComponent(label: label, value: value)
    }
}

private func isMetricChar(_ c: Character) -> Bool {
    c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "_" || c == "-")
}

private func isTagChar(_ c: Character) -> Bool {
    c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "_" || c == "-" || c == "/")
}
