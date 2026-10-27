//
//  ModelCatalog.swift
//  Sage
//
//  Unified source-of-truth for model supply: local models downloaded from
//  Hugging Face (install/progress/delete states) and cloud model IDs
//  discovered from the configured provider plus manual additions.
//

import Foundation
import HuggingFace
import Observation

@MainActor
@Observable
final class ModelCatalog {
    static let shared = ModelCatalog()

    enum LocalModelState: Equatable, Sendable {
        case notInstalled
        case downloading(progress: Double)
        case installed(diskBytes: Int64)
        case failed(reason: String)
    }

    struct FeaturedModel: Identifiable, Equatable, Sendable {
        let repoID: String
        let summary: String

        var id: String { repoID }
    }

    struct HubModelSearchResult: Identifiable, Equatable, Sendable {
        let repoID: String
        let downloads: Int?
        let likes: Int?

        var id: String { repoID }
    }

    /// Curated, known-good MLX builds; annotated by scale per the plan's
    /// small-model guidance (0.6B is a trial tier, 4B+ recommended).
    static let featuredModels: [FeaturedModel] = [
        FeaturedModel(
            repoID: "mlx-community/Qwen3-0.6B-4bit",
            summary: "0.6B · ~0.5 GB · Trial tier; not for real tasks"
        ),
        FeaturedModel(
            repoID: "mlx-community/Qwen3-1.7B-4bit",
            summary: "1.7B · ~1.2 GB · Light chat and simple tasks"
        ),
        FeaturedModel(
            repoID: "mlx-community/Qwen3-4B-4bit",
            summary: "4B · ~2.5 GB · Recommended for plan / execute"
        ),
        FeaturedModel(
            repoID: "mlx-community/Qwen3-8B-4bit",
            summary: "8B · ~4.9 GB · Stronger reasoning and review"
        ),
        FeaturedModel(
            repoID: "mlx-community/Qwen3-30B-A3B-4bit",
            summary: "30B MoE · ~18 GB · High-memory Macs"
        ),
    ]

    /// repoID → state for every local model the UI knows about.
    private(set) var localStates: [String: LocalModelState] = [:]

    /// Model IDs discovered from the provider's `/models` endpoint (cached).
    private(set) var cloudModelIDs: [String] = []

    /// Model IDs the user typed in manually (persisted).
    private(set) var manualCloudModelIDs: [String] = []

    private(set) var isFetchingCloudModels = false

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private enum DefaultsKey {
        static let manualCloudModels = "catalog.manualCloudModels"
        static let fetchedCloudModels = "catalog.fetchedCloudModels"
    }

    private init() {
        manualCloudModelIDs = Self.loadStringArray(DefaultsKey.manualCloudModels)
        cloudModelIDs = Self.loadStringArray(DefaultsKey.fetchedCloudModels)
        refreshInstalledModels()
    }

    // MARK: - Derived

    /// Repo IDs with a complete local snapshot — what the server may serve.
    var installedLocalModelIDs: [String] {
        localStates.compactMap { repoID, state in
            if case .installed = state { return repoID }
            return nil
        }.sorted()
    }

    /// Fetched + manual cloud IDs, deduplicated and sorted.
    var allCloudModelIDs: [String] {
        var seen = Set<String>()
        return (cloudModelIDs + manualCloudModelIDs).filter { seen.insert($0).inserted }.sorted()
    }

    // MARK: - Local installs

    /// Rescans the Hugging Face cache directory. Preserves in-flight download
    /// and failure states; everything found becomes `.installed`.
    func refreshInstalledModels() {
        let cacheDirectory = HubCache.default.cacheDirectory
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        var fresh: [String: LocalModelState] = [:]
        for entry in entries where entry.hasPrefix("models--") {
            let repoID = entry
                .dropFirst("models--".count)
                .replacingOccurrences(of: "--", with: "/")
            let repoDirectory = cacheDirectory.appendingPathComponent(entry)
            guard Self.isInstalled(repoDirectory: repoDirectory) else { continue }
            fresh[String(repoID)] = .installed(diskBytes: Self.blobsSize(repoDirectory: repoDirectory))
        }
        for (repoID, state) in localStates {
            switch state {
            case .downloading, .failed:
                fresh[repoID] = state
            case .notInstalled, .installed:
                break
            }
        }
        localStates = fresh
    }

    func localState(for repoID: String) -> LocalModelState {
        localStates[repoID] ?? .notInstalled
    }

    private static func isInstalled(repoDirectory: URL) -> Bool {
        let snapshots = repoDirectory.appendingPathComponent("snapshots")
        let commits = (try? FileManager.default.contentsOfDirectory(atPath: snapshots.path)) ?? []
        for commit in commits {
            let directory = snapshots.appendingPathComponent(commit)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            let hasConfig = files.contains("config.json")
            let hasWeights = files.contains { $0.hasSuffix(".safetensors") }
            if hasConfig && hasWeights { return true }
        }
        return false
    }

    private static func blobsSize(repoDirectory: URL) -> Int64 {
        let blobs = repoDirectory.appendingPathComponent("blobs")
        let enumerator = FileManager.default.enumerator(at: blobs, includingPropertiesForKeys: [
            .isRegularFileKey, .fileSizeKey,
        ])
        var total: Int64 = 0
        while let next = enumerator?.nextObject() as? URL {
            let values = try? next.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Downloads

    func startDownload(repoID: String) {
        guard downloadTasks[repoID] == nil else { return }
        localStates[repoID] = .downloading(progress: 0)
        let task = Task { [weak self] in
            await self?.performDownload(repoID: repoID)
        }
        downloadTasks[repoID] = task
    }

    func cancelDownload(repoID: String) {
        downloadTasks[repoID]?.cancel()
        downloadTasks[repoID] = nil
        localStates[repoID] = .notInstalled
    }

    func deleteModel(repoID: String) {
        downloadTasks[repoID]?.cancel()
        downloadTasks[repoID] = nil
        guard let repo = Repo.ID(rawValue: repoID) else { return }
        let repoDirectory = HubCache.default.repoDirectory(repo: repo, kind: .model)
        try? FileManager.default.removeItem(at: repoDirectory)
        localStates.removeValue(forKey: repoID)
        Task {
            if await LocalModelEngine.shared.loadedModelID == repoID {
                await LocalModelEngine.shared.unload()
            }
        }
    }

    private func performDownload(repoID: String) async {
        do {
            try await downloadSnapshot(repoID: repoID)
            downloadTasks[repoID] = nil
            refreshInstalledModels()
        } catch is CancellationError {
            downloadTasks[repoID] = nil
            localStates[repoID] = .notInstalled
        } catch {
            downloadTasks[repoID] = nil
            localStates[repoID] = .failed(reason: error.localizedDescription)
        }
    }

    private func downloadSnapshot(repoID: String) async throws {
        guard let repo = Repo.ID(rawValue: repoID) else {
            throw ModelCatalogError.invalidRepositoryID(repoID)
        }
        let firstEndpoint = await HubEndpointResolver.shared.resolve()
        let firstClient = HubClient(host: firstEndpoint.baseURL)
        do {
            _ = try await firstClient.downloadSnapshot(of: repo) { @MainActor progress in
                self.updateDownloadProgress(repoID: repoID, fraction: progress.fractionCompleted)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Retry once against a freshly probed endpoint (CN mirror fallback).
            await HubEndpointResolver.shared.invalidateCache()
            let retryEndpoint = await HubEndpointResolver.shared.resolve()
            let retryClient = HubClient(host: retryEndpoint.baseURL)
            _ = try await retryClient.downloadSnapshot(of: repo) { @MainActor progress in
                self.updateDownloadProgress(repoID: repoID, fraction: progress.fractionCompleted)
            }
        }
    }

    private func updateDownloadProgress(repoID: String, fraction: Double) {
        guard case .downloading = localStates[repoID] else { return }
        localStates[repoID] = .downloading(progress: min(max(fraction, 0), 1))
    }

    // MARK: - Hub search

    func searchHubModels(_ query: String) async -> [HubModelSearchResult] {
        let endpoint = await HubEndpointResolver.shared.resolve()
        let client = HubClient(host: endpoint.baseURL)
        do {
            let page = try await client.listModels(
                search: query.isEmpty ? nil : query,
                author: "mlx-community",
                sort: "downloads",
                direction: .descending,
                limit: 30
            )
            return page.items.map { model in
                HubModelSearchResult(
                    repoID: model.id.rawValue,
                    downloads: model.downloads,
                    likes: model.likes
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Cloud catalog

    func refreshCloudModels() async {
        guard !isFetchingCloudModels else { return }
        let settings = ModelSettings.shared
        let trimmedBase = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty, let url = URL(string: "\(trimmedBase)/models") else { return }
        isFetchingCloudModels = true
        defer { isFetchingCloudModels = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15

        struct ListResponse: Decodable {
            struct Entry: Decodable {
                let id: String
            }
            let data: [Entry]
        }

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let decoded = try? JSONDecoder().decode(ListResponse.self, from: data)
        else { return }

        cloudModelIDs = decoded.data.map(\.id).sorted()
        persist(cloudModelIDs, forKey: DefaultsKey.fetchedCloudModels)
    }

    func addManualCloudModel(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !manualCloudModelIDs.contains(trimmed) else { return }
        manualCloudModelIDs.append(trimmed)
        manualCloudModelIDs.sort()
        persist(manualCloudModelIDs, forKey: DefaultsKey.manualCloudModels)
    }

    func removeManualCloudModel(_ id: String) {
        manualCloudModelIDs.removeAll { $0 == id }
        persist(manualCloudModelIDs, forKey: DefaultsKey.manualCloudModels)
    }

    // MARK: - Persistence

    private func persist(_ array: [String], forKey key: String) {
        let data = try? JSONEncoder().encode(array)
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadStringArray(_ key: String) -> [String] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return array
    }
}

nonisolated enum ModelCatalogError: LocalizedError, Sendable {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            return "Invalid Hugging Face repository ID: \(id)"
        }
    }
}
