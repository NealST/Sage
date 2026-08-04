//
//  LocalModelService.swift
//  Sage
//
//  Manages a small on-device language model (via MLX) for task routing
//  and topic generation. The model runs entirely offline after the
//  initial download.
//

import Foundation
import MLX
import MLXLLM
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

    /// The HuggingFace model ID used for routing and topic generation.
    private static let modelID = "mlx-community/Qwen3-0.6B-4bit"

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

    // MARK: - Public

    /// Ensures the model is downloaded and loaded. Safe to call multiple times.
    func warmUp() async {
        guard modelContainer == nil else { return }
        await loadModel()
    }

    /// Returns true when the model is loaded and ready for inference.
    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// Runs a short text generation and returns the full output string.
    ///
    /// - Parameters:
    ///   - prompt: The complete prompt (system + user) to send.
    ///   - maxTokens: Upper bound on generated tokens (keep small for classification).
    ///   - temperature: Sampling temperature. Use 0 for deterministic classification.
    /// - Returns: The generated text.
    func generate(
        prompt: String,
        maxTokens: Int = 64,
        temperature: Float = 0
    ) async throws -> String {
        let container = try await ensureLoaded()

        let result = try await container.perform { context in
            let input = try await context.processor.prepare(
                input: .init(prompt: prompt)
            )
            var output = [String]()
            let parameters = GenerateParameters(temperature: temperature)

            let _ = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            ) { tokens in
                if let token = tokens.last,
                   let text = context.tokenizer.decode(tokens: [token]) as String?,
                   !text.isEmpty {
                    output.append(text)
                }
                return tokens.count >= maxTokens ? .stop : .more
            }
            return output.joined()
        }
        return result
    }

    /// Releases the model from memory. Next `generate` call will reload it.
    func unload() {
        modelContainer = nil
        status = .idle
        MLX.GPU.clearCache()
    }

    // MARK: - Private

    private func ensureLoaded() async throws -> ModelContainer {
        if let container = modelContainer { return container }
        return try await loadModel()
    }

    @discardableResult
    private func loadModel() async throws -> ModelContainer {
        status = .loading

        do {
            let configuration = ModelConfiguration.id(Self.modelID) {
                progress in
                Task { @Sendable [weak self] in
                    await self?.updateDownloadProgress(progress.fractionCompleted)
                }
            }

            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            )

            // Limit MLX buffer cache to keep memory footprint small.
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            modelContainer = container
            status = .ready
            return container
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    private func updateDownloadProgress(_ fraction: Double) {
        status = .downloading(progress: fraction)
    }
}
