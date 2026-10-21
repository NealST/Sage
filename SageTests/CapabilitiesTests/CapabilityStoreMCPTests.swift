//
//  CapabilityStoreMCPTests.swift
//  Sage
//
//  Regression tests for the MCP connection-coordination fixes:
//  a planned disconnect must not fire the exit callback, and exit
//  callbacks carrying a stale client identity must be ignored.
//

@testable import Sage
import XCTest

@MainActor
final class CapabilityStoreMCPTests: XCTestCase {
    private var tempDirectory: URL?

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapabilityStoreMCPTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirectory = dir
    }

    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func makeStore() -> CapabilityStore {
        let url = (tempDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("mcp-\(UUID().uuidString).json")
        return CapabilityStore(store: MCPConfigStore(fileURL: url))
    }

    /// `/bin/cat` echoes every stdin line back on stdout, which satisfies the
    /// JSON-RPC handshake: echoed requests carry the same id and resume as null
    /// results, so `connect()` completes without a real MCP server.
    private func catServer(id: String = "cat-server") -> MCPServerConfig {
        MCPServerConfig(id: id, name: id, command: "/bin/cat")
    }

    @discardableResult
    private func pollUntil(
        _ store: CapabilityStore,
        serverID: String,
        status: MCPServerStatus,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let server = store.mcpServers.first(where: { $0.id == serverID }),
               server.status == status {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    func testPlannedDisconnectDoesNotFireExitCallback() async throws {
        let client = MCPStdioClient(config: catServer())
        let recorder = ExitCallbackRecorder()
        await client.setOnProcessExit { serverID, _ in
            await recorder.record(serverID)
        }
        _ = try await client.connect()
        await client.disconnect()
        // Give the reader task time to observe the late EOF after forceCleanup.
        try await Task.sleep(for: .milliseconds(500))
        let count = await recorder.count
        XCTAssertEqual(count, 0, "a planned disconnect must not fire onProcessExit")
    }

    func testStaleExitIdentityIsIgnoredWhileCurrentClientSurvives() async throws {
        let store = makeStore()
        _ = store.addMCPServer(catServer())
        let connected = await pollUntil(store, serverID: "cat-server", status: .connected)
        XCTAssertTrue(connected, "expected the /bin/cat server to connect")

        guard let currentClient = store.clients["cat-server"] else {
            return XCTFail("expected a live client after connect")
        }

        // A stale identity, as if an already-replaced client reported its exit.
        let staleClient = MCPStdioClient(config: catServer())
        await store.handleServerProcessExit(
            serverID: "cat-server",
            exitedIdentity: ObjectIdentifier(staleClient)
        )
        var server = store.mcpServers.first { $0.id == "cat-server" }
        XCTAssertEqual(server?.status, .connected, "a stale exit must not disturb the live client")
        XCTAssertNotNil(store.clients["cat-server"], "a stale exit must not remove the live client")

        // The live client's own exit is actionable: it removes the client and
        // schedules a reconnect.
        await store.handleServerProcessExit(
            serverID: "cat-server",
            exitedIdentity: ObjectIdentifier(currentClient)
        )
        server = store.mcpServers.first { $0.id == "cat-server" }
        XCTAssertEqual(server?.status, .reconnecting, "the live client's exit should schedule a reconnect")
        XCTAssertNil(store.clients["cat-server"], "the live client's exit should remove the client")

        // Teardown: cancel the pending reconnect, drain the operation queue,
        // and terminate the process that the fabricated exit left running.
        store.setMCPEnabled("cat-server", enabled: false)
        await store.disconnectServers(["cat-server"])
        await currentClient.disconnect()
    }
}

private actor ExitCallbackRecorder {
    private var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }

    var count: Int { values.count }
}
