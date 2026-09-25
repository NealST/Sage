//
//  executed_tool_calls.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/models/executed_tool_calls.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Byte-budget helpers use JSONEncoder (serde_json::to_vec equivalent).
//  `floor_char_boundary` is implemented with UTF-8 prefix truncation.
//

import Foundation

let maxExecutedToolCallArgumentBytes = 8 * 1024
/// Maximum distinct result sources retained for one tool invocation.
let maxToolResultSources = 32
/// Maximum UTF-8 bytes for each source's `type` and `id` separately.
public let maxToolResultSourceFieldBytes = 128
let maxExecutedToolCallMetadataBytes = 2 * 1024 * 1024
let resourceAccessMetadataKey = "openai/resource_access"
let executedToolCallMetadataFieldBytes = "\"executed_tool_calls\":".utf8.count
let internalChatMessageMetadataPassthroughFieldBytes =
    "\"internal_chat_message_metadata_passthrough\":".utf8.count

private func jsonBytes<T: Encodable>(_ value: T) -> Int {
    (try? JSONEncoder().encode(value))?.count ?? Int.max
}

func executedToolCallMetadataFieldBytes(
    _ metadata: InternalChatMessageMetadataPassthrough
) -> Int {
    let fields = InternalChatMessageMetadataPassthrough(
        turnId: nil,
        createTime: nil,
        contentItemKinds: nil,
        cellId: metadata.cellId,
        executedToolCalls: nil,
        toolCallsComplete: metadata.toolCallsComplete)
    var bytes = max(0, jsonBytes(fields) - 2)
    if metadata.executedToolCalls != nil {
        bytes = bytes.saturatingAdd(bytes > 0 ? 1 : 0)
            .saturatingAdd(executedToolCallMetadataFieldBytes)
    }
    if bytes == 0 {
        return 0
    } else if metadata.turnId != nil || metadata.createTime != nil
        || metadata.contentItemKinds != nil
    {
        return bytes + 1
    } else {
        return bytes + internalChatMessageMetadataPassthroughFieldBytes + 3
    }
}

/// Returns the exact serialized wire size of an item's attempted-tool metadata.
public func executedToolCallMetadataBytes(_ item: ResponseItem) -> Int {
    guard let metadata = item.executedToolCallMetadata() else { return 0 }
    let callsBytes = metadata.executedToolCalls.map { jsonBytes($0) } ?? 0
    return callsBytes.saturatingAdd(executedToolCallMetadataFieldBytes(metadata))
}

extension InternalChatMessageMetadataPassthrough {
    /// Compares call order, names and arguments, ignoring optional result metadata.
    public func hasSameToolCalls(_ calls: [ExecutedToolCall]) -> Bool {
        guard let recorded = executedToolCalls, recorded.count == calls.count else {
            return false
        }
        return zip(recorded, calls).allSatisfy { recorded, call in
            recorded.name == call.name && recorded.arguments() == call.arguments()
        }
    }
}

/// Bounds attempted-tool metadata fairly across the complete serialized request.
public func boundExecutedToolCallsForPrompt(_ items: inout [ResponseItem]) {
    boundExecutedToolCallsForPromptWithPriority(&items, prioritizeRecent: false)
}

/// Bounds retained history without letting older calls displace the newest calls.
public func boundExecutedToolCallsForPromptPrioritizingRecent(_ items: inout [ResponseItem]) {
    items.reverse()
    boundExecutedToolCallsForPromptWithPriority(&items, prioritizeRecent: true)
    items.reverse()
}

func boundExecutedToolCallsForPromptWithPriority(
    _ items: inout [ResponseItem],
    prioritizeRecent: Bool
) {
    var damagedCells = Set<String>()
    for index in items.indices {
        _ = items[index].modifyInternalChatMessageMetadata { optional in
            guard var metadata = optional else { return }
            var truncated = false
            if var calls = metadata.executedToolCalls {
                for callIndex in calls.indices {
                    let argumentBytes = jsonBytes(calls[callIndex].storedArguments)
                    if calls[callIndex].truncation() == nil
                        && argumentBytes > maxExecutedToolCallArgumentBytes
                    {
                        calls[callIndex].setTruncation(
                            originalBytes: argumentBytes,
                            maxBytes: maxExecutedToolCallArgumentBytes,
                            omittedCalls: nil)
                    }
                    truncated = truncated || calls[callIndex].truncation() != nil
                }
                metadata.executedToolCalls = calls
            }
            if truncated {
                metadata.toolCallsComplete = nil
                if let cellId = metadata.cellId { damagedCells.insert(cellId) }
            }
            optional = metadata
        }
    }
    clearDamagedCellCompleteness(&items, damagedCells)

    boundExecutedToolCallsWithMetadataBudget(
        &items,
        maxMetadataBytes: maxExecutedToolCallMetadataBytes,
        prioritizeRecent: prioritizeRecent,
        wholeMessage: false)
}

/// Bounds optional observations to the space left in the actual outgoing message.
public func boundExecutedToolCallsForMessage(
    _ items: inout [ResponseItem],
    maxMetadataBytes: Int
) {
    boundExecutedToolCallsWithMetadataBudget(
        &items,
        maxMetadataBytes: maxMetadataBytes,
        prioritizeRecent: false,
        wholeMessage: true)
}

func boundExecutedToolCallsWithMetadataBudget(
    _ items: inout [ResponseItem],
    maxMetadataBytes: Int,
    prioritizeRecent: Bool,
    wholeMessage: Bool
) {
    var damagedCells = Set<String>()
    let totalMetadataBytes = metadataBytes(items)
    if totalMetadataBytes <= maxMetadataBytes { return }

    var remainingBytes = shedGenericResultMetadata(
        &items,
        maxMetadataBytes: maxMetadataBytes,
        prioritizeRecent: prioritizeRecent,
        wholeMessage: wholeMessage,
        totalMetadataBytes: totalMetadataBytes)

    if wholeMessage && metadataBytes(items) > maxMetadataBytes {
        let overageBytes = shedResultSources(&items, maxMetadataBytes: maxMetadataBytes, wholeMessage: true)
        if overageBytes > 0 {
            truncateCallArgumentsToFit(
                &items,
                maxMetadataBytes: maxMetadataBytes,
                overageBytes: overageBytes,
                damagedCells: &damagedCells)
        }
        remainingBytes = metadataBytes(items)
    }
    shedRemainingResultMetadata(
        &items,
        maxMetadataBytes: maxMetadataBytes,
        prioritizeRecent: prioritizeRecent,
        wholeMessage: wholeMessage,
        totalMetadataBytes: remainingBytes)

    if metadataBytes(items) <= maxMetadataBytes { return }
    for index in items.indices {
        items[index].clearToolResultMetadata()
    }
    if metadataBytes(items) <= maxMetadataBytes { return }
    if !wholeMessage {
        _ = shedResultSources(&items, maxMetadataBytes: maxMetadataBytes, wholeMessage: false)
    }
    if metadataBytes(items) <= maxMetadataBytes { return }
    distributeRemainingBudget(
        &items,
        maxMetadataBytes: maxMetadataBytes,
        prioritizeRecent: prioritizeRecent,
        damagedCells: &damagedCells)
    clearDamagedCellCompleteness(&items, damagedCells)
}

func metadataBytes(_ items: [ResponseItem]) -> Int {
    items.reduce(0) { $0.saturatingAdd(executedToolCallMetadataBytes($1)) }
}

struct ResultMetadataRef {
    var bytes: Int
    var evictionOrder: Int
    var callIndex: Int
    var itemIndex: Int
    var executedCallIndex: Int
}

func resultMetadataBySize(
    _ items: inout [ResponseItem],
    prioritizeRecent: Bool
) -> [ResultMetadataRef] {
    var resultMetadata: [ResultMetadataRef] = []
    for (itemIndex, item) in items.enumerated() {
        guard let metadata = item.internalChatMessageMetadataPassthrough(),
              let calls = metadata.executedToolCalls
        else { continue }
        let evictionOrder = prioritizeRecent ? Int.max - itemIndex : itemIndex
        for (callIndex, call) in calls.enumerated() where call.toolResultMetadata.isSome {
            resultMetadata.append(
                ResultMetadataRef(
                    bytes: jsonBytes(call.toolResultMetadata),
                    evictionOrder: evictionOrder,
                    callIndex: callIndex,
                    itemIndex: itemIndex,
                    executedCallIndex: callIndex))
        }
    }
    resultMetadata.sort {
        if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
        if $0.evictionOrder != $1.evictionOrder { return $0.evictionOrder < $1.evictionOrder }
        return $0.callIndex < $1.callIndex
    }
    return resultMetadata
}

private func updateCallMetadata(
    _ items: inout [ResponseItem],
    itemIndex: Int,
    callIndex: Int,
    _ body: (inout ExecutedToolCall) -> Void
) {
    _ = items[itemIndex].modifyInternalChatMessageMetadata { optional in
        guard var metadata = optional, var calls = metadata.executedToolCalls,
              calls.indices.contains(callIndex)
        else { return }
        body(&calls[callIndex])
        metadata.executedToolCalls = calls
        optional = metadata
    }
}

func shedGenericResultMetadata(
    _ items: inout [ResponseItem],
    maxMetadataBytes: Int,
    prioritizeRecent: Bool,
    wholeMessage: Bool,
    totalMetadataBytes: Int
) -> Int {
    var totalMetadataBytes = totalMetadataBytes
    var resultMetadata = resultMetadataBySize(&items, prioritizeRecent: prioritizeRecent)
    for index in resultMetadata.indices {
        if totalMetadataBytes <= maxMetadataBytes { break }
        var metadata = ToolResultMetadata()
        updateCallMetadata(&items, itemIndex: resultMetadata[index].itemIndex,
                           callIndex: resultMetadata[index].executedCallIndex) {
            metadata = $0.toolResultMetadata
        }
        let bytes = resultMetadata[index].bytes
        if metadata.retainResourceAccess() {
            let retainedBytes = jsonBytes(metadata)
            totalMetadataBytes = totalMetadataBytes.saturatingSub(bytes.saturatingSub(retainedBytes))
            resultMetadata[index].bytes = retainedBytes
            updateCallMetadata(&items, itemIndex: resultMetadata[index].itemIndex,
                               callIndex: resultMetadata[index].executedCallIndex) {
                $0.setToolResultMetadata(metadata)
            }
        } else {
            let retainedBytes = metadata.omitIfSmaller(
                originalBytes: bytes,
                overageBytes: totalMetadataBytes - maxMetadataBytes)
            totalMetadataBytes = totalMetadataBytes.saturatingSub(bytes - retainedBytes)
            resultMetadata[index].bytes = retainedBytes
            updateCallMetadata(&items, itemIndex: resultMetadata[index].itemIndex,
                               callIndex: resultMetadata[index].executedCallIndex) {
                $0.setToolResultMetadata(metadata)
            }
        }
    }
    if wholeMessage {
        for index in resultMetadata.indices {
            if totalMetadataBytes <= maxMetadataBytes { break }
            var metadata = ToolResultMetadata()
            updateCallMetadata(&items, itemIndex: resultMetadata[index].itemIndex,
                               callIndex: resultMetadata[index].executedCallIndex) {
                metadata = $0.toolResultMetadata
            }
            if metadata.retainResourceAccess() { continue }
            updateCallMetadata(&items, itemIndex: resultMetadata[index].itemIndex,
                               callIndex: resultMetadata[index].executedCallIndex) {
                $0.setToolResultMetadata(ToolResultMetadata())
            }
            totalMetadataBytes = totalMetadataBytes.saturatingSub(
                resultMetadata[index].bytes.saturatingAdd("\"tool_result_metadata\":".utf8.count + 1))
            resultMetadata[index].bytes = 0
        }
    }
    return totalMetadataBytes
}

func shedRemainingResultMetadata(
    _ items: inout [ResponseItem],
    maxMetadataBytes: Int,
    prioritizeRecent: Bool,
    wholeMessage: Bool,
    totalMetadataBytes: Int
) {
    var totalMetadataBytes = totalMetadataBytes
    var resultMetadata = resultMetadataBySize(&items, prioritizeRecent: prioritizeRecent)
    for index in resultMetadata.indices {
        if totalMetadataBytes <= maxMetadataBytes { break }
        var metadata = ToolResultMetadata()
        updateCallMetadata(&items, itemIndex: resultMetadata[index].itemIndex,
                           callIndex: resultMetadata[index].executedCallIndex) {
            metadata = $0.toolResultMetadata
        }
        let retainedBytes = metadata.omitIfSmaller(
            originalBytes: resultMetadata[index].bytes,
            overageBytes: totalMetadataBytes - maxMetadataBytes)
        totalMetadataBytes = totalMetadataBytes.saturatingSub(
            resultMetadata[index].bytes - retainedBytes)
        resultMetadata[index].bytes = retainedBytes
        updateCallMetadata(&items, itemIndex: resultMetadata[index].itemIndex,
                           callIndex: resultMetadata[index].executedCallIndex) {
            $0.setToolResultMetadata(metadata)
        }
    }
    resultMetadata.sort { lhs, rhs in
        var lhsMeta = ToolResultMetadata()
        var rhsMeta = ToolResultMetadata()
        updateCallMetadata(&items, itemIndex: lhs.itemIndex, callIndex: lhs.executedCallIndex) {
            lhsMeta = $0.toolResultMetadata
        }
        updateCallMetadata(&items, itemIndex: rhs.itemIndex, callIndex: rhs.executedCallIndex) {
            rhsMeta = $0.toolResultMetadata
        }
        let lhsOmitted = lhsMeta.isOmittedDueToSizeLimit()
        let rhsOmitted = rhsMeta.isOmittedDueToSizeLimit()
        let lhsWhole = wholeMessage && !lhsOmitted
        let rhsWhole = wholeMessage && !rhsOmitted
        if lhsWhole != rhsWhole { return lhsWhole && !rhsWhole }
        if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
        if !lhsOmitted != !rhsOmitted { return !lhsOmitted && rhsOmitted }
        if lhs.evictionOrder != rhs.evictionOrder { return lhs.evictionOrder < rhs.evictionOrder }
        return lhs.callIndex < rhs.callIndex
    }
    for ref in resultMetadata {
        if totalMetadataBytes <= maxMetadataBytes { break }
        var isNone = true
        updateCallMetadata(&items, itemIndex: ref.itemIndex, callIndex: ref.executedCallIndex) {
            isNone = $0.toolResultMetadata.isNone
        }
        if isNone { continue }
        updateCallMetadata(&items, itemIndex: ref.itemIndex, callIndex: ref.executedCallIndex) {
            $0.setToolResultMetadata(ToolResultMetadata())
        }
        totalMetadataBytes = totalMetadataBytes.saturatingSub(
            ref.bytes.saturatingAdd("\"tool_result_metadata\":".utf8.count + 1))
    }
}

func shedResultSources(
    _ items: inout [ResponseItem],
    maxMetadataBytes: Int,
    wholeMessage: Bool
) -> Int {
    var overageBytes = metadataBytes(items).saturatingSub(maxMetadataBytes)
    for index in items.indices {
        _ = items[index].modifyInternalChatMessageMetadata { optional in
            guard var metadata = optional, var calls = metadata.executedToolCalls else { return }
            for callIndex in calls.indices {
                if wholeMessage && overageBytes == 0 { break }
                if let sources = calls[callIndex].takeToolResultSources() {
                    let bytes = jsonBytes(sources)
                    overageBytes = overageBytes.saturatingSub(
                        bytes.saturatingAdd("\"tool_result_sources\":".utf8.count + 1))
                }
            }
            metadata.executedToolCalls = calls
            optional = metadata
        }
    }
    return overageBytes
}

func truncateCallArgumentsToFit(
    _ items: inout [ResponseItem],
    maxMetadataBytes: Int,
    overageBytes: Int,
    damagedCells: inout Set<String>
) {
    var overageBytes = overageBytes
    for index in items.indices {
        while overageBytes > 0 {
            var argumentsChanged = false
            _ = items[index].modifyInternalChatMessageMetadata { optional in
                guard var metadata = optional, var calls = metadata.executedToolCalls else { return }
                for callIndex in calls.indices {
                    if calls[callIndex].truncation() != nil { continue }
                    let originalBytes = jsonBytes(calls[callIndex].storedArguments)
                    let truncated: ExecutedToolCallArguments = .truncated(
                        truncation: ExecutedToolCallTruncation(
                            originalBytes: originalBytes,
                            maxBytes: min(
                                originalBytes.saturatingSub(overageBytes),
                                maxExecutedToolCallArgumentBytes),
                            omittedCalls: nil,
                            originalNameBytes: nil))
                    let truncatedBytes = jsonBytes(truncated)
                    if truncatedBytes < originalBytes {
                        calls[callIndex].storedArguments = truncated
                        argumentsChanged = true
                        metadata.toolCallsComplete = nil
                        if let cellId = metadata.cellId { damagedCells.insert(cellId) }
                        break
                    }
                }
                metadata.executedToolCalls = calls
                optional = metadata
            }
            if !argumentsChanged { break }
            clearDamagedCellCompleteness(&items, damagedCells)
            overageBytes = metadataBytes(items).saturatingSub(maxMetadataBytes)
        }
    }
}

func distributeRemainingBudget(
    _ items: inout [ResponseItem],
    maxMetadataBytes: Int,
    prioritizeRecent: Bool,
    damagedCells: inout Set<String>
) {
    var remainingItems = items.filter { executedToolCallMetadataBytes($0) > 0 }.count
    var remainingBytes = maxMetadataBytes
    for index in items.indices {
        let itemBytes = executedToolCallMetadataBytes(items[index])
        if itemBytes == 0 { continue }
        let itemBudget = prioritizeRecent ? remainingBytes : remainingBytes / max(remainingItems, 1)
        if itemBytes > itemBudget {
            if let cellId = items[index].executedToolCallMetadata()?.cellId {
                damagedCells.insert(cellId)
            }
            items[index].clearToolCallsComplete()
            items[index].boundExecutedToolCallsWithBudget(itemBudget)
        }
        remainingBytes = remainingBytes.saturatingSub(executedToolCallMetadataBytes(items[index]))
        remainingItems -= 1
    }
}

func clearDamagedCellCompleteness(_ items: inout [ResponseItem], _ damagedCells: Set<String>) {
    for index in items.indices {
        if let cellId = items[index].executedToolCallMetadata()?.cellId,
           damagedCells.contains(cellId)
        {
            items[index].clearToolCallsComplete()
        }
    }
}

/// Raw model arguments or trusted truncation metadata for an attempted tool call.
public enum ExecutedToolCallArguments: Equatable, Sendable {
    case raw(JSONValue)
    case truncated(truncation: ExecutedToolCallTruncation)
}

extension ExecutedToolCallArguments: Codable {
    public init(from decoder: any Decoder) throws {
        self = .raw(try JSONValue(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .raw(let value):
            try value.encode(to: encoder)
        case .truncated(let truncation):
            var container = encoder.container(keyedBy: TruncationKey.self)
            try container.encode(truncation, forKey: .truncated)
        }
    }

    private enum TruncationKey: String, CodingKey {
        case truncated = "_codex_executed_tool_call_truncated"
    }
}

public struct ExecutedToolCall: Codable, Equatable, Sendable {
    public var name: String
    var storedArguments: ExecutedToolCallArguments
    var toolResultSources: [ToolResultSource]?
    var toolResultMetadata: ToolResultMetadata

    enum CodingKeys: String, CodingKey {
        case name, arguments
        case toolResultSources = "tool_result_sources"
        case toolResultMetadata = "tool_result_metadata"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        storedArguments = try container.decode(ExecutedToolCallArguments.self, forKey: .arguments)
        // skip_deserializing
        toolResultSources = nil
        toolResultMetadata = ToolResultMetadata()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(storedArguments, forKey: .arguments)
        try container.encodeIfPresent(toolResultSources, forKey: .toolResultSources)
        if !toolResultMetadata.isNone {
            try container.encode(toolResultMetadata, forKey: .toolResultMetadata)
        }
    }

    public init(name: String, arguments: JSONValue) {
        let wrapped: JSONValue
        if case .object(let object) = arguments,
           object["_codex_executed_tool_call_truncated"] != nil
        {
            wrapped = .object(["_codex_executed_tool_call_raw": arguments])
        } else {
            wrapped = arguments
        }
        self.name = name
        self.storedArguments = .raw(wrapped)
        self.toolResultSources = nil
        self.toolResultMetadata = ToolResultMetadata()
    }

    public static func truncated(name: String, originalBytes: Int, maxBytes: Int) -> ExecutedToolCall {
        var call = ExecutedToolCall(name: name, arguments: .null)
        call.setTruncation(originalBytes: originalBytes, maxBytes: maxBytes, omittedCalls: nil)
        return call
    }

    public func arguments() -> ExecutedToolCallArguments { storedArguments }

    @discardableResult
    public mutating func setToolResultSources(_ sources: ToolResultSources) -> Bool {
        toolResultSources = sources.sources
        return toolResultSources != nil
    }

    public mutating func setToolResultMetadata(_ metadata: ToolResultMetadata) {
        toolResultMetadata = metadata
    }

    mutating func takeToolResultSources() -> [ToolResultSource]? {
        let sources = toolResultSources
        toolResultSources = nil
        return sources
    }

    func truncation() -> ExecutedToolCallTruncation? {
        if case .truncated(let truncation) = storedArguments { return truncation }
        return nil
    }

    mutating func setTruncation(originalBytes: Int, maxBytes: Int, omittedCalls: Int?) {
        setTruncationWithName(
            originalBytes: originalBytes, maxBytes: maxBytes,
            omittedCalls: omittedCalls, originalNameBytes: nil)
    }

    mutating func setTruncationWithName(
        originalBytes: Int, maxBytes: Int, omittedCalls: Int?, originalNameBytes: Int?
    ) {
        storedArguments = .truncated(
            truncation: ExecutedToolCallTruncation(
                originalBytes: originalBytes,
                maxBytes: maxBytes,
                omittedCalls: omittedCalls,
                originalNameBytes: originalNameBytes))
    }
}

public struct ToolResultMetadata: Equatable, Sendable {
    var value: JSONValue?

    public init(_ metadata: JSONValue? = nil) {
        self.value = metadata
    }

    public init(metadata: JSONValue) {
        self.value = metadata
    }

    public var isNone: Bool { value == nil }
    public var isSome: Bool { value != nil }

    mutating func retainResourceAccess() -> Bool {
        guard case .object(var metadata) = value,
              metadata[resourceAccessMetadataKey] != nil
        else { return false }
        metadata = metadata.filter { $0.key == resourceAccessMetadataKey }
        value = .object(metadata)
        return true
    }

    static func omittedDueToSizeLimit(overageBytes: Int) -> ToolResultMetadata {
        ToolResultMetadata(.string("omitted_due_to_size_limit (overage_bytes=\(overageBytes))"))
    }

    func isOmittedDueToSizeLimit() -> Bool {
        guard case .string(let text) = value else { return false }
        if text == "omitted_due_to_size_limit" { return true }
        guard text.hasPrefix("omitted_due_to_size_limit (overage_bytes="),
              text.hasSuffix(")")
        else { return false }
        let start = text.index(text.startIndex, offsetBy: "omitted_due_to_size_limit (overage_bytes=".count)
        let end = text.index(before: text.endIndex)
        return Int(text[start..<end]) != nil
    }

    mutating func omitIfSmaller(originalBytes: Int, overageBytes: Int) -> Int {
        if isNone || isOmittedDueToSizeLimit() { return originalBytes }
        let omitted = Self.omittedDueToSizeLimit(overageBytes: overageBytes)
        let omittedBytes = jsonBytes(omitted)
        if omittedBytes < originalBytes {
            self = omitted
            return omittedBytes
        }
        return originalBytes
    }
}

extension ToolResultMetadata: Codable {
    public init(from decoder: any Decoder) throws {
        value = try JSONValue(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        if let value {
            try value.encode(to: encoder)
        } else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

extension ToolResultMetadata: CustomDebugStringConvertible {
    public var debugDescription: String { "ToolResultMetadata([redacted])" }
}

public struct ToolResultSources: Equatable, Sendable {
    var sources: [ToolResultSource]?

    public init(_ sources: [ToolResultSource]) {
        var unique: [ToolResultSource] = []
        for source in sources {
            if unique.contains(source) { continue }
            if unique.count == maxToolResultSources
                || source.type_.utf8.count > maxToolResultSourceFieldBytes
                || source.id.utf8.count > maxToolResultSourceFieldBytes
            {
                self.sources = nil
                return
            }
            unique.append(source)
        }
        self.sources = unique
    }

    public static func parseFailed() -> ToolResultSources {
        var value = ToolResultSources([])
        value.sources = [ToolResultSource(type_: "parse_failed", id: "")]
        return value
    }
}

public struct ToolResultSource: Codable, Equatable, Sendable {
    public var type_: String
    public var id: String

    enum CodingKeys: String, CodingKey {
        case type_ = "type"
        case id
    }

    public init(type_: String, id: String) {
        self.type_ = type_; self.id = id
    }
}

public struct ExecutedToolCallTruncation: Codable, Equatable, Sendable {
    var originalBytes: Int
    var maxBytes: Int
    var omittedCalls: Int?
    var originalNameBytes: Int?

    enum CodingKeys: String, CodingKey {
        case originalBytes = "original_bytes"
        case maxBytes = "max_bytes"
        case omittedCalls = "omitted_calls"
        case originalNameBytes = "original_name_bytes"
    }

    public init(
        originalBytes: Int, maxBytes: Int, omittedCalls: Int? = nil, originalNameBytes: Int? = nil
    ) {
        self.originalBytes = originalBytes
        self.maxBytes = maxBytes
        self.omittedCalls = omittedCalls
        self.originalNameBytes = originalNameBytes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalBytes, forKey: .originalBytes)
        try container.encode(maxBytes, forKey: .maxBytes)
        try container.encodeIfPresent(omittedCalls, forKey: .omittedCalls)
        try container.encodeIfPresent(originalNameBytes, forKey: .originalNameBytes)
    }
}

extension ResponseItem {
    public func executedToolCallMetadata() -> InternalChatMessageMetadataPassthrough? {
        internalChatMessageMetadataPassthrough()
    }

    public mutating func setToolCallCellId(_ cellId: String) {
        _ = modifyInternalChatMessageMetadata { metadata in
            if metadata == nil { metadata = InternalChatMessageMetadataPassthrough() }
            metadata?.cellId = cellId
        }
    }

    public mutating func appendExecutedToolCalls(_ calls: [ExecutedToolCall]) {
        if calls.isEmpty { return }
        _ = modifyInternalChatMessageMetadata { metadata in
            if metadata == nil { metadata = InternalChatMessageMetadataPassthrough() }
            if metadata?.executedToolCalls == nil { metadata?.executedToolCalls = [] }
            metadata?.executedToolCalls?.append(contentsOf: calls)
        }
    }

    public mutating func markToolCallsComplete() {
        _ = modifyInternalChatMessageMetadata { metadata in
            if metadata == nil { metadata = InternalChatMessageMetadataPassthrough() }
            if metadata?.executedToolCalls == nil { metadata?.executedToolCalls = [] }
            metadata?.toolCallsComplete = true
        }
    }

    public mutating func clearToolCallsComplete() {
        _ = modifyInternalChatMessageMetadata { metadata in
            metadata?.toolCallsComplete = nil
        }
    }

    public func hasSameToolResultMetadata(_ other: ResponseItem) -> Bool {
        let lhs = resultMetadataTuples(self)
        let rhs = resultMetadataTuples(other)
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { a, b in
            a.index == b.index && a.name == b.name
                && a.arguments == b.arguments && a.metadata == b.metadata
        }
    }

    public func hasToolResultMetadata() -> Bool {
        executedToolCallMetadata()?.executedToolCalls?.contains { $0.toolResultMetadata.isSome } == true
    }

    public mutating func clearToolResultMetadata() {
        _ = modifyInternalChatMessageMetadata { metadata in
            guard var calls = metadata?.executedToolCalls else { return }
            for index in calls.indices {
                calls[index].setToolResultMetadata(ToolResultMetadata())
            }
            metadata?.executedToolCalls = calls
        }
    }

    public mutating func omitToolResultMetadata(overageBytes: Int) {
        _ = modifyInternalChatMessageMetadata { metadata in
            guard var calls = metadata?.executedToolCalls else { return }
            for index in calls.indices {
                let bytes = jsonBytes(calls[index].toolResultMetadata)
                _ = calls[index].toolResultMetadata.omitIfSmaller(
                    originalBytes: bytes, overageBytes: overageBytes)
            }
            metadata?.executedToolCalls = calls
        }
    }

    public mutating func retainToolResourceAccessOrOmitMetadata(overageBytes: Int) {
        _ = modifyInternalChatMessageMetadata { metadata in
            guard var calls = metadata?.executedToolCalls else { return }
            for index in calls.indices {
                if !calls[index].toolResultMetadata.retainResourceAccess() {
                    let bytes = jsonBytes(calls[index].toolResultMetadata)
                    _ = calls[index].toolResultMetadata.omitIfSmaller(
                        originalBytes: bytes, overageBytes: overageBytes)
                }
            }
            metadata?.executedToolCalls = calls
        }
    }

    public mutating func retainToolResourceAccess() {
        _ = modifyInternalChatMessageMetadata { metadata in
            guard var calls = metadata?.executedToolCalls else { return }
            for index in calls.indices {
                if !calls[index].toolResultMetadata.retainResourceAccess() {
                    calls[index].setToolResultMetadata(ToolResultMetadata())
                }
            }
            metadata?.executedToolCalls = calls
        }
    }

    mutating func boundExecutedToolCallsWithBudget(_ maxMetadataBytes: Int) {
        guard let metadata = executedToolCallMetadata() else { return }
        let maxCallBytes = maxMetadataBytes.saturatingSub(executedToolCallMetadataFieldBytes(metadata))
        var didClear = false
        _ = modifyInternalChatMessageMetadata { optional in
            guard var passthrough = optional, var calls = passthrough.executedToolCalls,
                  !calls.isEmpty
            else {
                didClear = true
                return
            }
            let representedCalls = calls.reduce(0) { count, call in
                count.saturatingAdd(1).saturatingAdd(call.truncation()?.omittedCalls ?? 0)
            }
            calls = [calls[0]]
            let originalBytes = calls[0].truncation()?.originalBytes ?? jsonBytes(calls[0].storedArguments)
            let originalNameBytes = calls[0].truncation()?.originalNameBytes
            let omittedCalls = representedCalls > 1 ? representedCalls - 1 : nil
            calls[0].setTruncationWithName(
                originalBytes: originalBytes,
                maxBytes: min(maxCallBytes, maxExecutedToolCallArgumentBytes),
                omittedCalls: omittedCalls,
                originalNameBytes: originalNameBytes)
            if jsonBytes(calls) > maxCallBytes {
                calls[0].setTruncationWithName(
                    originalBytes: originalBytes,
                    maxBytes: min(maxCallBytes, maxExecutedToolCallArgumentBytes),
                    omittedCalls: omittedCalls,
                    originalNameBytes: originalNameBytes ?? calls[0].name.utf8.count)
                let excessBytes = jsonBytes(calls).saturatingSub(maxCallBytes)
                calls[0].name = floorCharBoundary(
                    calls[0].name, maxBytes: max(0, calls[0].name.utf8.count - excessBytes))
            }
            passthrough.executedToolCalls = calls
            optional = passthrough
            if jsonBytes(calls) > maxCallBytes { didClear = true }
        }
        if didClear { clearExecutedToolCalls() }
    }

    public mutating func clearExecutedToolCalls() {
        _ = modifyInternalChatMessageMetadata { metadata in
            guard var passthrough = metadata else { return }
            passthrough.cellId = nil
            passthrough.executedToolCalls = nil
            passthrough.toolCallsComplete = nil
            if passthrough == InternalChatMessageMetadataPassthrough() {
                metadata = nil
            } else {
                metadata = passthrough
            }
        }
    }
}

private struct ResultMetadataTuple: Equatable {
    var index: Int
    var name: String
    var arguments: ExecutedToolCallArguments
    var metadata: ToolResultMetadata
}

private func resultMetadataTuples(_ item: ResponseItem) -> [ResultMetadataTuple] {
    guard let calls = item.executedToolCallMetadata()?.executedToolCalls else { return [] }
    return calls.enumerated().compactMap { index, call in
        guard call.toolResultMetadata.isSome else { return nil }
        return ResultMetadataTuple(
            index: index, name: call.name,
            arguments: call.arguments(), metadata: call.toolResultMetadata)
    }
}

private func floorCharBoundary(_ string: String, maxBytes: Int) -> String {
    if string.utf8.count <= maxBytes { return string }
    var count = 0
    var end = string.startIndex
    for index in string.indices {
        let scalarBytes = String(string[index]).utf8.count
        if count + scalarBytes > maxBytes { break }
        count += scalarBytes
        end = string.index(after: index)
    }
    return String(string[..<end])
}

private extension Int {
    func saturatingAdd(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? Int.max : result
    }

    func saturatingSub(_ other: Int) -> Int {
        let (result, overflow) = subtractingReportingOverflow(other)
        return overflow ? 0 : Swift.max(result, 0)
    }
}
