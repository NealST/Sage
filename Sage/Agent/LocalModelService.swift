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
import MLXHuggingFace
import MLXLMCommon

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
    }

    private(set) var status: Status = .idle
    private var modelContainer: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?
    private var retryCount = 0
    private static let maxRetries = 2

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
                using: #huggingFaceTokenizerLoader(),
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

// MARK: - Custom Downloader

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
            throw HuggingFaceDownloaderError.invalidRepositoryID(id)
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
