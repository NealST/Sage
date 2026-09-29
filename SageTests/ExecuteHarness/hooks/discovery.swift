//
//  discovery.swift
//  SageTests
//
//  Port of selected cases from
//  codex-rs/hooks/src/engine/discovery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  append_matcher_groups cases are ported. ConfigLayerStack / TOML layer
//  tests are skipped until that stack exists.
//

@testable import CodexHooks
import CodexProtocol
import CodexUtils
import XCTest

final class HooksDiscoveryTests: XCTestCase {
    func testMcpToolHooksPreserveArgumentTemplatesAndListTheirTarget() throws {
        let sourcePath = try discoverySourcePath()
        let input: [String: JSONValue] = [
            "file_path": .string("${tool_input.file_path}"),
            "optional": .string("${tool_input.optional}"),
        ]
        var handlers: [ConfiguredHandler] = []
        var entries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &entries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .postToolUse,
            groups: [
                MatcherGroup(
                    matcher: "Write|Edit",
                    hooks: [
                        .mcpTool(
                            server: "security",
                            tool: "scan",
                            input: input,
                            timeoutSec: 30,
                            statusMessage: "Scanning file"
                        ),
                    ]
                ),
            ]
        )

        XCTAssertTrue(warnings.isEmpty)
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].handler, .mcpTool(server: "security", tool: "scan"))
        XCTAssertTrue(entries[0].currentHash.hasPrefix("sha256:"))
    }

    func testSessionEndMcpToolHooksAreWarnedAndSkipped() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var entries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &entries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .sessionEnd,
            groups: [
                MatcherGroup(
                    matcher: nil,
                    hooks: [
                        .mcpTool(
                            server: "security",
                            tool: "scan",
                            input: [:],
                            timeoutSec: nil,
                            statusMessage: nil
                        ),
                    ]
                ),
            ]
        )

        XCTAssertTrue(handlers.isEmpty)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(
            warnings,
            ["skipping MCP tool hook in \(sourcePath.display): SessionEnd MCP hooks are not supported"]
        )
    }

    func testInterruptMcpToolHooksAreSupportedAndTimeoutIsClamped() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var entries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &entries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .interrupt,
            groups: [
                MatcherGroup(
                    matcher: nil,
                    hooks: [
                        .mcpTool(
                            server: "security",
                            tool: "scan",
                            input: [:],
                            timeoutSec: nil,
                            statusMessage: nil
                        ),
                        .mcpTool(
                            server: "security",
                            tool: "report",
                            input: [:],
                            timeoutSec: 600,
                            statusMessage: nil
                        ),
                    ]
                ),
            ]
        )

        XCTAssertEqual(handlers.map(\.timeoutSec), [1, 3])
        XCTAssertEqual(entries.map(\.timeoutSec), [1, 3])
        XCTAssertTrue(entries.allSatisfy {
            if case .mcpTool = $0.handler { return true }
            return false
        })
        XCTAssertEqual(
            warnings,
            ["clamping Interrupt hook timeout to 3s in \(sourcePath.display)"]
        )
    }

    func testSupportedEventsRetainPerHandlerAdditionalContextLimitAndHashIt() throws {
        for eventName: HookEventName in [
            .preToolUse, .postToolUse, .sessionStart, .userPromptSubmit, .subagentStart,
        ] {
            let (_, defaultEntry, _) = try discoverCommand(eventName, additionalContextLimit: nil)
            let (explicitDefaultHandler, explicitDefaultEntry, _) = try discoverCommand(
                eventName,
                additionalContextLimit: DEFAULT_HOOK_OUTPUT_TOKEN_LIMIT
            )
            let (customHandler, customEntry, _) = try discoverCommand(
                eventName,
                additionalContextLimit: 20_000
            )
            let (unlimitedHandler, unlimitedEntry, _) = try discoverCommand(
                eventName,
                additionalContextLimit: 0
            )

            XCTAssertEqual(
                customHandler.additionalContextLimit,
                AdditionalContextLimit.fromConfig(20_000)
            )
            XCTAssertEqual(customEntry.additionalContextLimit, 20_000)
            XCTAssertNotEqual(defaultEntry.currentHash, customEntry.currentHash)
            XCTAssertEqual(
                explicitDefaultHandler.additionalContextLimit,
                AdditionalContextLimit.fromConfig(DEFAULT_HOOK_OUTPUT_TOKEN_LIMIT)
            )
            XCTAssertEqual(
                explicitDefaultEntry.additionalContextLimit,
                DEFAULT_HOOK_OUTPUT_TOKEN_LIMIT
            )
            XCTAssertEqual(defaultEntry.currentHash, explicitDefaultEntry.currentHash)
            XCTAssertEqual(
                unlimitedHandler.additionalContextLimit,
                AdditionalContextLimit.fromConfig(0)
            )
            XCTAssertEqual(unlimitedEntry.additionalContextLimit, 0)
            XCTAssertNotEqual(defaultEntry.currentHash, unlimitedEntry.currentHash)
        }
    }

    func testUnsupportedEventWarnsAndIgnoresAdditionalContextLimit() throws {
        let sourcePath = try discoverySourcePath()
        let (handler, _, warnings) = try discoverCommand(.stop, additionalContextLimit: 4_096)

        XCTAssertEqual(handler.additionalContextLimit, .default)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("ignoring additionalContextLimit for Stop hook"))
        XCTAssertTrue(warnings[0].contains(sourcePath.display))
    }

    func testUserPromptSubmitIgnoresInvalidMatcherDuringDiscovery() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .userPromptSubmit,
            groups: [commandGroup("[")]
        )

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(
            handlers,
            [
                ConfiguredHandler(
                    eventName: .userPromptSubmit,
                    timeoutSec: 600,
                    sourcePath: .local(sourcePath),
                    source: .system,
                    displayOrder: 0,
                    kind: .command(command: "echo hello", env: [:], isAsync: false)
                ),
            ]
        )
    }

    func testPreToolUseKeepsValidMatcherDuringDiscovery() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .preToolUse,
            groups: [commandGroup("^Bash$")]
        )

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(
            handlers,
            [
                ConfiguredHandler(
                    eventName: .preToolUse,
                    matcher: "^Bash$",
                    timeoutSec: 600,
                    sourcePath: .local(sourcePath),
                    source: .system,
                    displayOrder: 0,
                    kind: .command(command: "echo hello", env: [:], isAsync: false)
                ),
            ]
        )
    }

    func testSessionEndNormalizesTimeout() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .sessionEnd,
            groups: [
                MatcherGroup(
                    matcher: "other",
                    hooks: [
                        .command(
                            command: "echo default",
                            commandWindows: nil,
                            timeoutSec: nil,
                            isAsync: false,
                            statusMessage: nil,
                            additionalContextLimit: nil
                        ),
                        .command(
                            command: "echo clamped",
                            commandWindows: nil,
                            timeoutSec: 600,
                            isAsync: true,
                            statusMessage: nil,
                            additionalContextLimit: nil
                        ),
                    ]
                ),
            ]
        )

        XCTAssertEqual(handlers.map(\.timeoutSec), [1, 3])
        XCTAssertTrue(handlers.allSatisfy { $0.canApplyControlEffects() })
        XCTAssertEqual(handlers.map(\.matcher), ["other", "other"])
        XCTAssertEqual(hookEntries.map(\.timeoutSec), [1, 3])
        XCTAssertTrue(hookEntries.allSatisfy {
            if case .command(_, let isAsync) = $0.handler { return !isAsync }
            return false
        })
        XCTAssertEqual(hookEntries.map(\.matcher), ["other", "other"])
        XCTAssertEqual(
            warnings,
            [
                "clamping SessionEnd hook timeout to 3s in \(sourcePath.display)",
                "running async SessionEnd hook synchronously in \(sourcePath.display)",
            ]
        )
    }

    func testInterruptNormalizesTimeoutAndSupportsAsyncExecution() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .interrupt,
            groups: [
                MatcherGroup(
                    matcher: "ignored",
                    hooks: [
                        .command(
                            command: "echo interrupt",
                            commandWindows: nil,
                            timeoutSec: 600,
                            isAsync: true,
                            statusMessage: nil,
                            additionalContextLimit: nil
                        ),
                    ]
                ),
            ]
        )

        var unused: [String] = []
        XCTAssertEqual(
            normalizeCommandHook(.interrupt, timeoutSec: nil, sourcePath: sourcePath, warnings: &unused),
            1
        )
        XCTAssertEqual(handlers.map(\.timeoutSec), [3])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertNil(handlers[0].matcher)
        XCTAssertEqual(handlers[0].executionMode(), .async)
        XCTAssertEqual(hookEntries.map(\.timeoutSec), [3])
        XCTAssertNil(hookEntries[0].matcher)
        XCTAssertTrue(hookEntries.allSatisfy {
            if case .command(_, let isAsync) = $0.handler { return isAsync }
            return false
        })
        XCTAssertEqual(
            warnings,
            ["clamping Interrupt hook timeout to 3s in \(sourcePath.display)"]
        )
    }

    func testBypassHookTrustAllowsEnabledUntrustedHandlers() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = unmanagedHookHandlerSource(sourcePath, bypassHookTrust: true)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .preToolUse,
            groups: [commandGroup("Bash")]
        )

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(hookEntries.count, 1)
        XCTAssertEqual(hookEntries[0].trustStatus, .untrusted)
        XCTAssertEqual(hookEntries[0].enabled, true)
    }

    func testBypassHookTrustRespectsDisabledHandlers() throws {
        let sourcePath = try discoverySourcePath()
        let hookStates = [
            "\(sourcePath.display):pre_tool_use:0:0": HookStateToml(enabled: false),
        ]
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = unmanagedHookHandlerSource(
            sourcePath,
            hookStates: hookStates,
            bypassHookTrust: true
        )

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .preToolUse,
            groups: [commandGroup("Bash")]
        )

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(handlers, [])
        XCTAssertEqual(hookEntries.count, 1)
        XCTAssertEqual(hookEntries[0].trustStatus, .untrusted)
        XCTAssertEqual(hookEntries[0].enabled, false)
    }

    func testPreToolUseTreatsStarMatcherAsMatchAll() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .preToolUse,
            groups: [commandGroup("*")]
        )

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(handlers[0].matcher, "*")
    }

    func testPostToolUseKeepsValidMatcherDuringDiscovery() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .postToolUse,
            groups: [commandGroup("Edit|Write")]
        )

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(handlers[0].eventName, .postToolUse)
        XCTAssertEqual(handlers[0].matcher, "Edit|Write")
    }

    func testPreToolUseResolvesWindowsCommandOverrideDuringDiscovery() throws {
        let sourcePath = try discoverySourcePath()
        var handlers: [ConfiguredHandler] = []
        var hookEntries: [HookListEntry] = []
        var warnings: [String] = []
        var requiredLoadErrors: [String] = []
        var displayOrder: Int64 = 0
        var source = managedHookHandlerSource(sourcePath)

        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: .preToolUse,
            groups: [
                MatcherGroup(
                    matcher: "^Bash$",
                    hooks: [
                        .command(
                            command: "echo unix",
                            commandWindows: "echo windows",
                            timeoutSec: nil,
                            isAsync: false,
                            statusMessage: nil,
                            additionalContextLimit: nil
                        ),
                    ]
                ),
            ]
        )

        XCTAssertEqual(warnings, [])
        XCTAssertEqual(handlers.count, 1)
        #if os(Windows)
        let expected = "echo windows"
        #else
        let expected = "echo unix"
        #endif
        XCTAssertEqual(
            handlers[0].kind,
            .command(command: expected, env: [:], isAsync: false)
        )
    }

    func testLoadHooksJsonParsesCommandAndMcpHandlers() throws {
        let folder = try makeTempHooksFolder()
        defer { try? FileManager.default.removeItem(atPath: folder.path) }
        try writeHooksJSON(
            folder,
            """
            {
              "hooks": {
                "PreToolUse": [{
                  "matcher": "^Bash$",
                  "hooks": [{ "type": "command", "command": "echo hello" }]
                }],
                "PostToolUse": [{
                  "matcher": "Write|Edit",
                  "hooks": [{
                    "type": "mcp_tool",
                    "server": "security",
                    "tool": "scan",
                    "input": { "file_path": "${tool_input.file_path}" }
                  }]
                }]
              }
            }
            """
        )

        var warnings: [String] = []
        let loaded = loadHooksJson(folder, warnings: &warnings)
        XCTAssertTrue(warnings.isEmpty)
        let events = try XCTUnwrap(loaded?.1)
        XCTAssertEqual(events.preToolUse.count, 1)
        XCTAssertEqual(events.preToolUse[0].matcher, "^Bash$")
        XCTAssertEqual(events.postToolUse[0].matcher, "Write|Edit")
        if case .mcpTool(_, _, let input, _, _)? = events.postToolUse[0].hooks.first {
            XCTAssertEqual(input["file_path"], .string("${tool_input.file_path}"))
        } else {
            XCTFail("expected MCP handler")
        }
    }

    func testLoadHooksJsonWarnsOnMalformedFile() throws {
        let folder = try makeTempHooksFolder()
        defer { try? FileManager.default.removeItem(atPath: folder.path) }
        try writeHooksJSON(folder, "{not json")

        var warnings: [String] = []
        XCTAssertNil(loadHooksJson(folder, warnings: &warnings))
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("failed to parse hooks config"))
        XCTAssertTrue(warnings[0].contains(folder.join("hooks.json").display))
    }

    func testDiscoverHandlersLoadsUserHooksJsonWithoutTrust() throws {
        let folder = try makeTempHooksFolder()
        defer { try? FileManager.default.removeItem(atPath: folder.path) }
        try writeHooksJSON(
            folder,
            """
            {
              "hooks": {
                "PreToolUse": [{
                  "matcher": "^Bash$",
                  "hooks": [{ "type": "command", "command": "echo hello" }]
                }]
              }
            }
            """
        )

        let listed = discoverHandlers(hooksJsonFolders: [folder])
        XCTAssertTrue(listed.handlers.isEmpty)
        XCTAssertEqual(listed.hookEntries.count, 1)
        XCTAssertEqual(listed.hookEntries[0].trustStatus, .untrusted)
        XCTAssertEqual(listed.hookEntries[0].matcher, "^Bash$")

        let trusted = discoverHandlers(hooksJsonFolders: [folder], bypassHookTrust: true)
        XCTAssertEqual(trusted.handlers.count, 1)
        XCTAssertEqual(trusted.handlers[0].eventName, .preToolUse)
        XCTAssertEqual(trusted.handlers[0].kind, .command(command: "echo hello", env: [:], isAsync: false))
    }

    func testListHooksReadsHooksJsonFolder() throws {
        let folder = try makeTempHooksFolder()
        defer { try? FileManager.default.removeItem(atPath: folder.path) }
        try writeHooksJSON(
            folder,
            """
            {
              "hooks": {
                "SessionStart": [{
                  "hooks": [{ "type": "command", "command": "echo start" }]
                }]
              }
            }
            """
        )

        let outcome = listHooks(
            HooksConfig(featureEnabled: true, hooksJsonFolders: [folder])
        )
        XCTAssertEqual(outcome.hooks.count, 1)
        XCTAssertEqual(outcome.hooks[0].eventName, .sessionStart)
        XCTAssertEqual(outcome.warnings, [])
    }
}

private func discoverySourcePath() throws -> AbsolutePathBuf {
    try AbsolutePathBuf.fromAbsolutePath("/tmp/hooks.json")
}

private func commandGroup(_ matcher: String?) -> MatcherGroup {
    MatcherGroup(
        matcher: matcher,
        hooks: [
            .command(
                command: "echo hello",
                commandWindows: nil,
                timeoutSec: nil,
                isAsync: false,
                statusMessage: nil,
                additionalContextLimit: nil
            ),
        ]
    )
}

private func commandGroup(additionalContextLimit: Int) -> MatcherGroup {
    MatcherGroup(
        matcher: nil,
        hooks: [
            .command(
                command: "echo hello",
                commandWindows: nil,
                timeoutSec: nil,
                isAsync: false,
                statusMessage: nil,
                additionalContextLimit: additionalContextLimit
            ),
        ]
    )
}

private func discoverCommand(
    _ eventName: HookEventName,
    additionalContextLimit: Int?
) throws -> (ConfiguredHandler, HookListEntry, [String]) {
    let sourcePath = try discoverySourcePath()
    var handlers: [ConfiguredHandler] = []
    var entries: [HookListEntry] = []
    var warnings: [String] = []
    var requiredLoadErrors: [String] = []
    var displayOrder: Int64 = 0
    var source = managedHookHandlerSource(sourcePath)
    appendMatcherGroups(
        handlers: &handlers,
        hookEntries: &entries,
        warnings: &warnings,
        requiredLoadErrors: &requiredLoadErrors,
        displayOrder: &displayOrder,
        source: &source,
        eventName: eventName,
        groups: [
            additionalContextLimit.map(commandGroup(additionalContextLimit:)) ?? commandGroup(nil),
        ]
    )
    return (handlers.removeFirst(), entries.removeFirst(), warnings)
}

private func makeTempHooksFolder() throws -> AbsolutePathBuf {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sage-hooks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try AbsolutePathBuf.fromAbsolutePath(url.path)
}

private func writeHooksJSON(_ folder: AbsolutePathBuf, _ contents: String) throws {
    try contents.write(toFile: folder.join("hooks.json").path, atomically: true, encoding: .utf8)
}
