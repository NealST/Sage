//
//  LocalModelEngine.swift
//  Sage
//
//  Owns the on-device MLX model lifecycle: load, swap on demand,
//  warm-up, streaming generation, and memory-pressure unloading.
//

import Foundation
import Observation

// MARK: - Shared surface (all architectures)

nonisolated enum LocalModelEngineError: LocalizedError, Sendable {
    case unsupportedArchitecture

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            return "Local models require Apple Silicon (MLX)."
        }
    }
}

nonisolated enum LocalModelEngineStatus: Sendable, Equatable {
    case idle
    case loading(modelID: String)
    case downloading(modelID: String, progress: Double)
    case ready(modelID: String)
    case failed(modelID: String, reason: String)

    var modelID: String? {
        switch self {
        case .idle:
            return nil
        case .loading(let modelID), .downloading(let modelID, _), .ready(let modelID), .failed(let modelID, _):
            return modelID
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .downloading:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// UI-facing mirror of the engine state; the engine publishes here so both
/// the composer status row and the Models pane observe one source.
@MainActor @Observable
final class LocalEngineObserver {
    static let shared = LocalEngineObserver()

    private(set) var status: LocalModelEngineStatus = .idle

    private init() {}

    func update(_ status: LocalModelEngineStatus) {
        self.status = status
    }
}

/// Sendable chat message crossing the server → engine boundary.
nonisolated struct LocalChatMessage: Sendable, Equatable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    struct ToolCall: Sendable, Equatable {
        var id: String?
        var name: String
        var argumentsJSON: String
    }

    var role: Role
    var content: String?
    var toolCalls: [ToolCall]?
    var toolCallID: String?
}

nonisolated struct LocalGenerationRequest: Sendable {
    var modelID: String
    var messages: [LocalChatMessage]
    var tools: [[String: any Sendable]]?
    var temperature: Double?
    var maxTokens: Int?
}

nonisolated enum LocalGenerationEvent: Sendable {
    case text(String)
    case toolCall(ToolCallProposal)
    case finished(finishReason: String?)
}

// MARK: - Engine

#if arch(arm64)
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon

actor LocalModelEngine {
    static let shared = LocalModelEngine()

    nonisolated static let isAvailable = true

    private static let defaultMaxTokens = 8192
    private static let defaultTemperature = 0.6
    private static let mlxCacheLimitBytes = 20 * 1024 * 1024

    private var container: ModelContainer?
    private(set) var loadedModelID: String?
    /// The model currently being loaded; guards stale progress/failure
    /// publishes after a swap or unload cancelled the previous load.
    private var loadingModelID: String?
    private var loadTask: Task<ModelContainer, Error>?
    private var activeGenerations = 0
    private var pressureHandlingStarted = false

    // MARK: Lifecycle

    /// Wires the memory-pressure monitor. Call once at app startup.
    func start() {
        guard !pressureHandlingStarted else { return }
        pressureHandlingStarted = true
        MemoryPressureMonitor.shared.onPressureChange = { level in
            guard level == .critical else { return }
            Task { await LocalModelEngine.shared.unloadIfIdle() }
        }
        MemoryPressureMonitor.shared.start()
    }

    /// Loads the model if not already resident so the first chat is instant.
    func warmUp(modelID: String) async {
        do {
            _ = try await ensureLoaded(modelID: modelID)
        } catch {
            // Best effort: failures surface through the published status.
        }
    }

    func unloadIfIdle() async {
        guard activeGenerations == 0 else { return }
        await unload()
    }

    func unload() async {
        loadTask?.cancel()
        loadTask = nil
        loadingModelID = nil
        container = nil
        loadedModelID = nil
        MLX.Memory.clearCache()
        await publish(.idle)
    }

    // MARK: Generation

    func generate(
        _ request: LocalGenerationRequest
    ) async throws -> AsyncThrowingStream<LocalGenerationEvent, Error> {
        let container = try await ensureLoaded(modelID: request.modelID)
        let chat = request.messages.map(Self.chatMessage)
        let userInput = UserInput(
            chat: chat,
            tools: request.tools,
            additionalContext: ["enable_thinking": false]
        )
        let input = try await container.prepare(input: userInput)
        let parameters = GenerateParameters(
            maxTokens: request.maxTokens ?? Self.defaultMaxTokens,
            temperature: Float(request.temperature ?? Self.defaultTemperature)
        )
        let stream = try await container.generate(input: input, parameters: parameters)
        activeGenerations += 1
        return AsyncThrowingStream { continuation in
            let task = Task {
                var sawToolCall = false
                do {
                    for await generation in stream {
                        try Task.checkCancellation()
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(.text(text))
                        case .toolCall(let call):
                            sawToolCall = true
                            continuation.yield(.toolCall(Self.proposal(from: call)))
                        case .info:
                            break
                        }
                    }
                    continuation.yield(.finished(sawToolCall ? "tool_calls" : "stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.endGeneration() }
            }
        }
    }

    private func endGeneration() async {
        activeGenerations = max(activeGenerations - 1, 0)
    }

    // MARK: Loading

    private func ensureLoaded(modelID: String) async throws -> ModelContainer {
        if let container, loadedModelID == modelID {
            return container
        }
        if let task = loadTask {
            // Wait out any in-flight load so the swap below happens at most
            // once per queued request.
            let container = try await task.value
            if loadedModelID == modelID {
                return container
            }
        }
        container = nil
        loadedModelID = nil
        MLX.Memory.clearCache()
        let task = Task { try await performLoad(modelID) }
        loadTask = task
        do {
            let container = try await task.value
            loadTask = nil
            return container
        } catch {
            loadTask = nil
            throw error
        }
    }

    private func performLoad(_ modelID: String) async throws -> ModelContainer {
        loadingModelID = modelID
        await publish(.loading(modelID: modelID))
        do {
            let loaded = try await attemptLoad(modelID)
            MLX.Memory.cacheLimit = Self.mlxCacheLimitBytes
            if loadingModelID == modelID {
                container = loaded
                loadedModelID = modelID
                loadingModelID = nil
                await publish(.ready(modelID: modelID))
            }
            return loaded
        } catch is CancellationError {
            if loadingModelID == modelID {
                loadingModelID = nil
                container = nil
                loadedModelID = nil
                await publish(.idle)
            }
            throw CancellationError()
        } catch {
            let reason = error.localizedDescription
            if loadingModelID == modelID {
                loadingModelID = nil
                container = nil
                loadedModelID = nil
                await publish(.failed(modelID: modelID, reason: reason))
            }
            throw error
        }
    }

    private func attemptLoad(_ modelID: String) async throws -> ModelContainer {
        do {
            return try await downloadAndLoad(modelID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // One retry against a freshly probed endpoint (CN mirror fallback).
            await HubEndpointResolver.shared.invalidateCache()
            return try await downloadAndLoad(modelID)
        }
    }

    private func downloadAndLoad(_ modelID: String) async throws -> ModelContainer {
        let endpoint = await HubEndpointResolver.shared.resolve()
        let downloader = LocalModelHubDownloader(host: endpoint.baseURL)
        return try await LLMModelFactory.shared.loadContainer(
            from: downloader,
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: modelID),
            progressHandler: { progress in
                Task {
                    await self.noteDownloadProgress(
                        modelID: modelID,
                        fraction: progress.fractionCompleted
                    )
                }
            }
        )
    }

    private func noteDownloadProgress(modelID: String, fraction: Double) async {
        guard loadingModelID == modelID, fraction >= 0, fraction <= 1 else { return }
        await publish(.downloading(modelID: modelID, progress: fraction))
    }

    private func publish(_ status: LocalModelEngineStatus) async {
        await MainActor.run {
            LocalEngineObserver.shared.update(status)
        }
    }

    // MARK: Wire conversion

    private static func chatMessage(from message: LocalChatMessage) -> Chat.Message {
        switch message.role {
        case .system:
            return .system(message.content ?? "")
        case .user:
            return .user(message.content ?? "")
        case .assistant:
            let toolCalls = message.toolCalls?.map { call in
                MLXLMCommon.ToolCall(
                    function: .init(
                        name: call.name,
                        arguments: mlxArguments(fromJSON: call.argumentsJSON)
                    ),
                    id: call.id
                )
            }
            return .assistant(message.content ?? "", toolCalls: toolCalls)
        case .tool:
            return .tool(message.content ?? "", id: message.toolCallID)
        }
    }

    private static func mlxArguments(fromJSON json: String) -> [String: MLXLMCommon.JSONValue] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: MLXLMCommon.JSONValue].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func proposal(from call: MLXLMCommon.ToolCall) -> ToolCallProposal {
        let argumentsJSON: String
        if let data = try? JSONEncoder().encode(call.function.arguments),
           let encoded = String(data: data, encoding: .utf8) {
            argumentsJSON = encoded
        } else {
            argumentsJSON = "{}"
        }
        return ToolCallProposal(
            id: call.id ?? "local_\(UUID().uuidString.prefix(8))",
            name: call.function.name,
            argumentsJSON: argumentsJSON
        )
    }
}

/// Routes MLX model downloads through the endpoint resolver (official vs
/// CN mirror) and falls back to the local cache when the network is down.
private struct LocalModelHubDownloader: MLXLMCommon.Downloader, Sendable {
    let host: URL

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw ModelCatalogError.invalidRepositoryID(id)
        }
        let hubClient = HubClient(host: host)
        let resolvedRevision = revision ?? "main"
        do {
            return try await hubClient.downloadSnapshot(
                of: repoID,
                revision: resolvedRevision,
                matching: patterns,
                progressHandler: { @MainActor progress in
                    progressHandler(progress)
                }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await hubClient.downloadSnapshot(
                of: repoID,
                revision: resolvedRevision,
                matching: patterns,
                localFilesOnly: true,
                progressHandler: { @MainActor progress in
                    progressHandler(progress)
                }
            )
        }
    }
}

#else

// Intel fallback: MLX requires Apple Silicon. The same surface exists so
// call sites compile; local generation reports the unsupported-architecture
// error and the UI dims the local origin.
actor LocalModelEngine {
    static let shared = LocalModelEngine()

    nonisolated static let isAvailable = false

    private(set) var loadedModelID: String?

    func start() {}

    func warmUp(modelID: String) async {}

    func unloadIfIdle() async {}

    func unload() async {}

    func generate(
        _ request: LocalGenerationRequest
    ) async throws -> AsyncThrowingStream<LocalGenerationEvent, Error> {
        throw LocalModelEngineError.unsupportedArchitecture
    }
}

#endif
