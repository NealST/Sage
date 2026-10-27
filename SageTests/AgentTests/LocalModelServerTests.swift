//
//  LocalModelServerTests.swift
//  SageTests
//
//  Wire-level checks against the in-process OpenAI-compatible endpoint.
//  These exercise the transport contract (routing, status codes, error
//  envelopes) without needing model weights — unknown models 404 before the
//  engine is ever consulted.
//

import Foundation
import Testing
@testable import Sage

@MainActor
final class LocalModelServerTests {
    /// Boots the shared server and waits for its dynamic port. The server is
    /// a process-wide singleton; starting once per test run is enough.
    private func bootedBaseURL() async throws -> URL {
        LocalModelServer.shared.start()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let url = LocalModelServer.shared.endpointBaseURL {
                return url
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CocoaError(.userActivityConnectionUnavailable)
    }

    @Test
    func modelsEndpointListsInstalledModelsAsOpenAIList() async throws {
        let base = try await bootedBaseURL()
        let (data, response) = try await URLSession.shared.data(from: base.appending(path: "models"))

        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        struct ListResponse: Decodable {
            struct Entry: Decodable {
                let id: String
                let object: String
            }
            let object: String
            let data: [Entry]
        }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        #expect(decoded.object == "list")
        #expect(decoded.data.allSatisfy { $0.object == "model" })
        // Entries match what the catalog would serve.
        for entry in decoded.data {
            #expect(!entry.id.isEmpty)
        }
    }

    @Test
    func chatCompletionsRejectsUndownloadedModel() async throws {
        let base = try await bootedBaseURL()

        let body: [String: Any] = [
            "model": "org/definitely-not-downloaded-4bit",
            "messages": [["role": "user", "content": "hi"]],
        ]
        var request = URLRequest(url: base.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 404)
        struct ErrorResponse: Decodable {
            struct Payload: Decodable {
                let message: String
                let type: String
            }
            let error: Payload
        }
        let decoded = try JSONDecoder().decode(ErrorResponse.self, from: data)
        #expect(decoded.error.type == "invalid_request_error")
        #expect(decoded.error.message.contains("not downloaded"))
    }

    @Test
    func chatCompletionsRejectsMalformedJSON() async throws {
        let base = try await bootedBaseURL()

        var request = URLRequest(url: base.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{not json".utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
    }

    @Test
    func missingEndpointFallsBackToUnroutableHost() {
        // Before the server binds, snapshots must route somewhere that fails
        // fast — never a real provider.
        #expect(LocalModelServer.unavailableBaseURLString.hasPrefix("http://127.0.0.1:1/"))
    }
}
