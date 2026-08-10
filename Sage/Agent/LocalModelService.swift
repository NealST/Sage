//
//  LocalModelService.swift
//  Sage
//
//  Manages a small on-device language model (via MLX) for task routing
//  and topic generation. The model runs entirely offline after the
//  initial download.
//

import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Singleton actor that owns the local MLX model lifecycle.
///
/// Responsibilities:
/// - One-time download + caching of the model weights
/// - Loading the model into memory on first use
/// - Running short inference calls (classification, topic generation)
/// - Unloading when memory pressure is high
actor LocalModelService {
    static let shared = LocalModelService()

    /// Use the registry configuration which includes `extraEOSTokens`.
    private static let modelConfiguration = LLMRegistry.qwen3_0_6b_4bit

    private let endpointResolver = HubEndpointResolver.shared

    // MARK: - State

    enum Status: Sendable {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case failed(String)
        /// Model was automatically unloaded due to system memory pressure.
        case unloadedByPressure
    }

    private(set) var status: Status = .idle
    private var modelContainer: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?
    private var retryCount = 0
    private static let maxRetries = 2

    /// True while a `generate` call is in flight — prevents mid-inference unload.
    private var isInferring = false
    /// Set when pressure arrives during inference; triggers unload after completion.
    private var shouldUnloadAfterInference = false

    // MARK: - Public

    /// Ensures the model is downloaded and loaded. Safe to call multiple times.
    func warmUp() async {
        guard modelContainer == nil else { return }
        _ = try? await ensureLoaded()
    }

    /// Returns true when the model is loaded and ready for inference.
    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// Runs a short text generation and returns the full output string.
    ///
    /// - Parameters:
    ///   - systemPrompt: The system instruction for the model.
    ///   - userPrompt: The user message content.
    ///   - maxTokens: Upper bound on generated tokens (keep small for classification).
    ///   - temperature: Sampling temperature. Use 0 for deterministic classification.
    /// - Returns: The generated text.
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 64,
        temperature: Float = 0
    ) async throws -> String {
        let container = try await ensureLoaded()

        isInferring = true
        defer {
            isInferring = false
            if shouldUnloadAfterInference {
                shouldUnloadAfterInference = false
                unloadDueToPressure()
            }
        }

        let userInput = UserInput(
            chat: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            additionalContext: ["enable_thinking": false]
        )

        let input = try await container.prepare(input: userInput)

        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature
        )

        let stream = try await container.generate(
            input: input,
            parameters: parameters
        )

        var output = ""
        for await generation in stream {
            if let chunk = generation.chunk {
                output += chunk
            }
        }
        return output
    }

    /// Releases the model from memory. Next `generate` call will reload it.
    func unload() {
        modelContainer = nil
        loadingTask?.cancel()
        loadingTask = nil
        status = .idle
        MLX.Memory.clearCache()
    }

    /// Called by the memory pressure monitor. Defers if inference is active.
    func handleMemoryPressure() {
        guard modelContainer != nil else { return }
        if isInferring {
            shouldUnloadAfterInference = true
        } else {
            unloadDueToPressure()
        }
    }

    /// Approximate memory used by the MLX model buffers (bytes).
    var memoryFootprintBytes: Int {
        Int(MLX.Memory.activeMemory)
    }

    private func unloadDueToPressure() {
        modelContainer = nil
        loadingTask?.cancel()
        loadingTask = nil
        status = .unloadedByPressure
        MLX.Memory.clearCache()
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> ModelContainer {
        if let container = modelContainer { return container }
        // Deduplicate concurrent load requests.
        if let existing = loadingTask {
            return try await existing.value
        }
        let task = Task { try await loadModel() }
        loadingTask = task
        do {
            let container = try await task.value
            loadingTask = nil
            return container
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private func loadModel() async throws -> ModelContainer {
        status = .loading

        do {
            let endpoint = await endpointResolver.resolve()
            let hubClient = HubClient(host: endpoint.baseURL)
            let downloader = SageHubDownloader(hubClient: hubClient) { [weak self] progress in
                Task { @Sendable [weak self] in
                    await self?.updateDownloadProgress(progress)
                }
            }

            let container = try await LLMModelFactory.shared.loadContainer(
                from: downloader,
                using: SageTransformersTokenizerLoader(),
                configuration: Self.modelConfiguration
            )

            // Limit MLX buffer cache to keep memory footprint small.
            MLX.Memory.cacheLimit = 20 * 1024 * 1024

            modelContainer = container
            status = .ready
            retryCount = 0
            return container
        } catch {
            // On download failure for CN users, invalidate endpoint cache and retry
            // with a fresh probe so the other endpoint gets a chance.
            if retryCount < Self.maxRetries {
                retryCount += 1
                await endpointResolver.invalidateCache()
                status = .idle
                return try await loadModel()
            }
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    private func updateDownloadProgress(_ fraction: Double) {
        status = .downloading(progress: fraction)
    }
}

// MARK: - Hub / Tokenizer adapters

private enum SageHubError: LocalizedError {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            "Invalid Hugging Face repository ID: '\(id)'. Expected format 'namespace/name'."
        }
    }
}

/// Wraps `HubClient` to conform to the MLXLMCommon `Downloader` protocol,
/// allowing us to control which endpoint (official vs mirror) is used.
private struct SageHubDownloader: MLXLMCommon.Downloader, @unchecked Sendable {
    let hubClient: HubClient
    let progressCallback: @Sendable (Double) -> Void

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw SageHubError.invalidRepositoryID(id)
        }
        let revision = revision ?? "main"
        return try await hubClient.downloadSnapshot(
            of: repoID,
            revision: revision,
            matching: patterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
                progressCallback(progress.fractionCompleted)
            }
        )
    }
}

/// Loads tokenizers via `swift-transformers` without depending on MLXHuggingFace macros.
private struct SageTransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return SageTokenizerBridge(upstream)
    }
}

private struct SageTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
