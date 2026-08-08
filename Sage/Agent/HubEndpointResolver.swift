//
//  HubEndpointResolver.swift
//  Sage
//
//  Resolves the best HuggingFace endpoint (official vs mirror) based on
//  the user's network conditions. Uses Locale as a fast pre-filter and
//  HEAD-request racing for CN-region users.
//

import Foundation

/// The resolved HuggingFace endpoint to use for model downloads.
nonisolated enum HubEndpoint: String, Sendable {
    case official = "https://huggingface.co"
    case mirror = "https://hf-mirror.com"

    var baseURL: URL { URL(string: rawValue)! }
}

/// Resolves and caches the best HuggingFace endpoint for the current network.
actor HubEndpointResolver {
    static let shared = HubEndpointResolver()

    private static let cacheKey = "sage.hubEndpoint"
    private static let cacheTimestampKey = "sage.hubEndpointTimestamp"
    /// Cache validity: 24 hours.
    private static let cacheTTL: TimeInterval = 86_400
    /// Timeout for each HEAD probe.
    private static let probeTimeout: TimeInterval = 5

    private var resolvedEndpoint: HubEndpoint?

    /// Returns the best endpoint, using cache when available.
    func resolve() async -> HubEndpoint {
        if let cached = resolvedEndpoint { return cached }
        if let cached = loadFromCache() {
            resolvedEndpoint = cached
            return cached
        }

        let endpoint = await determineEndpoint()
        resolvedEndpoint = endpoint
        persistToCache(endpoint)
        return endpoint
    }

    /// Forces a re-probe on next call (e.g., after a download failure).
    func invalidateCache() {
        resolvedEndpoint = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheTimestampKey)
    }

    // MARK: - Determination Logic

    private func determineEndpoint() async -> HubEndpoint {
        // Non-CN locale users: skip probing, use official directly.
        guard isLikelyCNLocale() else {
            return .official
        }

        // CN locale: race both endpoints to find the fastest reachable one.
        return await raceEndpoints()
    }

    private func isLikelyCNLocale() -> Bool {
        Locale.current.region?.identifier == "CN"
    }

    /// Sends concurrent HEAD requests to both endpoints; first 2xx wins.
    private func raceEndpoints() async -> HubEndpoint {
        let probePath = "/api/models"

        return await withTaskGroup(of: HubEndpoint?.self) { group in
            group.addTask {
                let ok = await self.probe(
                    url: HubEndpoint.official.baseURL.appendingPathComponent(probePath)
                )
                return ok ? .official : nil
            }
            group.addTask {
                let ok = await self.probe(
                    url: HubEndpoint.mirror.baseURL.appendingPathComponent(probePath)
                )
                return ok ? .mirror : nil
            }
            // Timeout fallback: if neither responds in time, default to official.
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.probeTimeout + 1))
                return .official
            }

            for await result in group {
                guard let endpoint = result else { continue }
                group.cancelAll()
                return endpoint
            }
            return .official
        }
    }

    private func probe(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = Self.probeTimeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<400).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Cache

    private func loadFromCache() -> HubEndpoint? {
        guard let raw = UserDefaults.standard.string(forKey: Self.cacheKey),
              let endpoint = HubEndpoint(rawValue: raw),
              let timestamp = UserDefaults.standard.object(forKey: Self.cacheTimestampKey) as? Double
        else {
            return nil
        }
        let age = Date.now.timeIntervalSince1970 - timestamp
        guard age < Self.cacheTTL else { return nil }
        return endpoint
    }

    private func persistToCache(_ endpoint: HubEndpoint) {
        UserDefaults.standard.set(endpoint.rawValue, forKey: Self.cacheKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.cacheTimestampKey)
    }
}
