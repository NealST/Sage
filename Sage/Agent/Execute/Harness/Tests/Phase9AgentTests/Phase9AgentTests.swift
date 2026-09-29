//
//  Phase9AgentTests.swift
//  Phase9AgentTests
//
//  Sage addition (no codex counterpart).
//  Phase 9 agent types, registry, roles, plugins, and apps tests.
//

import CodexAPI
import CodexAgentRoles
import CodexCore
import CodexHistory
import CodexProtocol
import CodexSkills
import CodexUtils
import Foundation
import XCTest

final class Phase9AgentTests: XCTestCase {
    func testFormatAgentNicknameOrdinals() {
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 0), "Ada")
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 1), "Ada the 2nd")
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 2), "Ada the 3rd")
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 3), "Ada the 4th")
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 10), "Ada the 11th")
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 11), "Ada the 12th")
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 12), "Ada the 13th")
        XCTAssertEqual(formatAgentNickname("Ada", nicknameResetCount: 20), "Ada the 21st")
    }

    func testThreadSpawnDepthHelpers() throws {
        let parent = ThreadId()
        let source = SessionSource.subAgent(
            .threadSpawn(
                parentThreadId: parent,
                depth: 1,
                agentPath: try AgentPath(string: "/root/child"),
                agentNickname: "Ada",
                agentRole: "explorer"
            )
        )
        XCTAssertEqual(nextThreadSpawnDepth(source), 2)
        XCTAssertEqual(nextThreadSpawnDepth(.cli), 1)
        XCTAssertFalse(exceedsThreadSpawnDepthLimit(depth: 2, maxDepth: 3))
        XCTAssertTrue(exceedsThreadSpawnDepthLimit(depth: 4, maxDepth: 3))
        XCTAssertEqual(source.getAgentPath()?.asStr, "/root/child")
        XCTAssertEqual(source.parentThreadId(), parent)
    }

    func testAgentRegistryReserveAndResolve() throws {
        let registry = AgentRegistry()
        let threadId = ThreadId()
        registry.registerRootThread(threadId)
        XCTAssertEqual(registry.agentIdForPath(.root()), threadId)

        var reservation = try registry.reserveSpawnSlot(maxThreads: 2)
        let nickname = try reservation.reserveAgentNicknameWithPreference(
            names: ["Ada", "Grace"],
            preferred: "Ada"
        )
        XCTAssertEqual(nickname, "Ada")
        let childPath = try AgentPath.root().join("ada")
        try reservation.reserveAgentPath(childPath)
        let childId = ThreadId()
        reservation.commit(
            AgentMetadata(
                agentId: childId,
                agentPath: childPath,
                agentNickname: nickname,
                agentRole: "explorer"
            )
        )
        XCTAssertEqual(registry.agentIdForPath(childPath), childId)
        XCTAssertEqual(registry.liveAgents().count, 1)
    }

    func testAgentRegistryEnforcesThreadLimit() {
        let registry = AgentRegistry()
        let held = try? registry.reserveSpawnSlot(maxThreads: 1)
        XCTAssertNotNil(held)
        XCTAssertThrowsError(try registry.reserveSpawnSlot(maxThreads: 1)) { error in
            guard let err = error as? CodexErr else {
                return XCTFail("expected CodexErr")
            }
            if case .agentLimitReached = err.detailsValue() {
                return
            }
            XCTFail("expected agentLimitReached, got \(err)")
        }
    }

    func testAgentStatusFromEventAdaptedTurnComplete() {
        XCTAssertEqual(
            agentStatusFromEvent(.turnStarted(TurnStartedEvent(turnId: "t1"))),
            .running
        )
        XCTAssertEqual(
            agentStatusFromEvent(
                .turnComplete(TurnCompleteEvent(turnId: "t1", interrupted: true))
            ),
            .interrupted
        )
        XCTAssertEqual(
            agentStatusFromEvent(.turnComplete(TurnCompleteEvent(turnId: "t1"))),
            .completed(nil)
        )
        XCTAssertEqual(
            agentStatusFromEvent(.error(ErrorEvent(message: "boom"))),
            .errored("boom")
        )
        XCTAssertNil(agentStatusFromEvent(.agentMessage(AgentMessageEvent(message: "hi"))))
        XCTAssertFalse(isFinal(.running))
        XCTAssertTrue(isFinal(.completed(nil)))
    }

    func testSpawnToolSpecListsBuiltInRoles() {
        let text = SpawnToolSpec.build(userDefinedAgentRoles: [:])
        XCTAssertTrue(text.hasPrefix("Available roles:\n"))
        XCTAssertTrue(text.contains("default: {"))
        XCTAssertTrue(text.contains("explorer: {"))
        XCTAssertTrue(text.contains("worker: {"))
        XCTAssertEqual(resolveRoleConfig(roleName: "default")?.description, "Default agent.")
        XCTAssertNil(resolveRoleConfig(roleName: "missing"))
    }

    func testRejectFullForkAndModelLookup() throws {
        XCTAssertNoThrow(try rejectFullForkAgentTypeOverride(nil))
        XCTAssertThrowsError(try rejectFullForkAgentTypeOverride("explorer"))

        let gpt = ModelPreset(id: "gpt", model: "gpt-5", displayName: "GPT", description: "d")
        let disabled = ModelPreset(
            id: "off",
            model: "off-model",
            displayName: "Off",
            description: "d",
            showInPicker: true,
            multiAgentVersion: .disabled
        )
        XCTAssertTrue(modelSupportsMultiAgentBackend(gpt, multiAgentVersion: .v1))
        XCTAssertFalse(modelSupportsMultiAgentBackend(disabled, multiAgentVersion: .v2))
        XCTAssertEqual(
            try findSpawnAgentModelName(
                availableModels: [gpt],
                requestedModel: "gpt-5",
                multiAgentVersion: .v2
            ),
            "gpt-5"
        )
        XCTAssertThrowsError(
            try findSpawnAgentModelName(
                availableModels: [gpt],
                requestedModel: "missing",
                multiAgentVersion: .v1
            )
        )
        XCTAssertNoThrow(
            try validateSpawnAgentReasoningEffort(
                model: "gpt-5",
                supportedReasoningLevels: [ReasoningEffortPreset(effort: .medium, description: "")],
                requestedReasoningEffort: .medium
            )
        )
        XCTAssertThrowsError(
            try validateSpawnAgentReasoningEffort(
                model: "gpt-5",
                supportedReasoningLevels: [ReasoningEffortPreset(effort: .low, description: "")],
                requestedReasoningEffort: .high
            )
        )
    }

    func testCollectExplicitPluginAndAppMentions() {
        let input: [UserInput] = [
            .text(text: "see [$calendar](app://calendar) and [@mail](plugin://mail@shop)", textElements: []),
            .mention(name: "notes", path: "plugin://notes@shop"),
        ]
        XCTAssertEqual(collectExplicitAppIds(input), ["calendar"])
        XCTAssertEqual(collectExplicitPluginIds(input), ["mail@shop", "notes@shop"])

        let plugins = [
            PluginCapabilitySummary(configName: "mail@shop", displayName: "Mail"),
            PluginCapabilitySummary(configName: "other", displayName: "Other"),
        ]
        XCTAssertEqual(
            collectExplicitPluginMentions(input, plugins: plugins).map(\.configName),
            ["mail@shop"]
        )
    }

    func testRenderExplicitPluginInstructionsAndBound() {
        let plugin = PluginCapabilitySummary(
            configName: "mail@shop",
            displayName: "Mail",
            pluginNamespace: "mail",
            hasSkills: true
        )
        let rendered = renderExplicitPluginInstructions(
            plugin: plugin,
            availableMcpServers: ["mail-mcp"],
            availableApps: ["Inbox"]
        )
        XCTAssertNotNil(rendered)
        XCTAssertTrue(rendered?.contains("Capabilities from the `Mail` plugin:") ?? false)
        XCTAssertTrue(rendered?.contains("prefixed with `mail:`") ?? false)
        XCTAssertTrue(rendered?.contains("`Inbox`") ?? false)
        XCTAssertTrue(rendered?.contains("`mail-mcp`") ?? false)

        let empty = renderExplicitPluginInstructions(
            plugin: PluginCapabilitySummary(configName: "x", displayName: "X"),
            availableMcpServers: [],
            availableApps: []
        )
        XCTAssertNil(empty)
    }

    func testRenderAppsSectionRequiresAccessibleAndEnabled() {
        XCTAssertNil(renderAppsSection([]))
        XCTAssertNil(
            renderAppsSection([
                AppInfo(id: "calendar", name: "Calendar", isAccessible: true, isEnabled: false)
            ])
        )
        XCTAssertNil(
            renderAppsSection([
                AppInfo(id: "calendar", name: "Calendar", isAccessible: false, isEnabled: true)
            ])
        )
        let rendered = renderAppsSection([
            AppInfo(id: "calendar", name: "Calendar", isAccessible: true, isEnabled: true)
        ])
        XCTAssertNotNil(rendered)
        XCTAssertTrue(rendered?.hasPrefix(appsInstructionsOpenTag) ?? false)
        XCTAssertTrue(rendered?.contains("## Apps (Connectors)") ?? false)
        XCTAssertTrue(rendered?.hasSuffix(appsInstructionsCloseTag) ?? false)
    }

    func testAgentMessageIntoCommunication() throws {
        let author = AgentPath.root()
        let recipient = try AgentPath.root().join("worker")
        let queued = AgentMessage.plaintext("hello").intoCommunication(
            author: author,
            recipient: recipient,
            mode: .queueOnly
        )
        XCTAssertFalse(queued.triggerTurn)
        XCTAssertTrue(queued.content.contains("Message Type: MESSAGE"))
        XCTAssertTrue(queued.content.contains("Payload:\nhello"))

        let encrypted = AgentMessage.encrypted("cipher").intoCommunication(
            author: author,
            recipient: recipient,
            mode: .triggerTurn
        )
        XCTAssertTrue(encrypted.triggerTurn)
        XCTAssertEqual(encrypted.encryptedContent, "cipher")
    }

    func testLocalAgentControlPathResolveAndServiceTier() throws {
        let control = LocalAgentControl()
        let rootId = ThreadId()
        control.runtime.registry.registerRootThread(rootId)
        var reservation = try control.runtime.registry.reserveSpawnSlot(maxThreads: 2)
        let childPath = try AgentPath.root().join("ada")
        try reservation.reserveAgentPath(childPath)
        let childId = ThreadId()
        reservation.commit(AgentMetadata(agentId: childId, agentPath: childPath))

        XCTAssertEqual(
            try control.resolveTarget(caller: rootId, target: .id(childId)),
            childId
        )
        XCTAssertEqual(
            try control.resolveTarget(caller: rootId, target: .reference("ada")),
            childId
        )
        control.setRootServiceTier("fast")
        XCTAssertEqual(control.serviceTier(), "fast")
        control.propagateConfigUpdate(.serviceTier(nil))
        XCTAssertNil(control.serviceTier())
        XCTAssertNil(control.admitTurn(version: .v1, source: .cli))
        XCTAssertNotNil(
            control.admitTurn(
                version: .v2,
                source: .subAgent(
                    .threadSpawn(
                        parentThreadId: rootId,
                        depth: 1,
                        agentPath: childPath,
                        agentNickname: nil,
                        agentRole: nil
                    )
                )
            )
        )
    }

    func testCyberAccessProgramRequiresChatgptAuth() {
        XCTAssertNil(forAuth(isChatgptAuth: false, program: .standard))
        XCTAssertEqual(forAuth(isChatgptAuth: true, program: .daybreakBlue)?.cyber, "daybreak_blue")
        XCTAssertNil(forAuth(isChatgptAuth: true, program: nil))
    }

    func testConnectorNameSlug() {
        XCTAssertEqual(connectorNameSlug("Google Calendar"), "google-calendar")
        XCTAssertEqual(connectorNameSlug("!!!"), "app")
        XCTAssertEqual(
            connectorMentionSlug(AppInfo(id: "cal", name: "Google Calendar")),
            "google-calendar"
        )
    }

    func testSpawnTelemetryLabels() {
        let records = recordSpawnSuccess(
            forkMode: .fullHistory,
            multiAgentVersion: .v2,
            measurements: SpawnMeasurements(
                historyMode: .paginated,
                residencyReservation: .seconds(1),
                childCreate: .milliseconds(2),
                durabilityWait: .milliseconds(3),
                inputAdmission: .milliseconds(4),
                total: .milliseconds(10)
            )
        )
        XCTAssertEqual(records.map(\.phase), [
            "residency_reservation", "child_create", "durability_wait", "input_admission", "total",
        ])
        XCTAssertEqual(records.first?.forkMode, "all")
        XCTAssertEqual(records.first?.historyMode, "paginated")
        XCTAssertEqual(records.first?.multiAgentVersion, "v2")
    }

    func testExecutionLimiterAdmitsV2SubAgentsOnly() throws {
        let control = LocalAgentControl()
        control.runtime.agentExecutionLimiter.initialize(1)
        let source = SessionSource.subAgent(
            .threadSpawn(
                parentThreadId: ThreadId(),
                depth: 1,
                agentPath: try AgentPath.root().join("ada"),
                agentNickname: nil,
                agentRole: nil
            )
        )
        XCTAssertNil(control.admitTurn(version: .v1, source: source))
        let held = control.admitTurn(version: .v2, source: source)
        XCTAssertNotNil(held)
        XCTAssertThrowsError(try control.checkTurnAdmission(version: .v2, source: source)) { error in
            guard let err = error as? CodexErr else {
                return XCTFail("expected CodexErr")
            }
            if case .agentLimitReached = err.detailsValue() { return }
            XCTFail("expected agentLimitReached, got \(err)")
        }
        _ = held
    }

    func testResidencySlotAndNicknameList() throws {
        let residency = V2Residency()
        let slot = try residency.reserveSlot(capacity: 1)
        XCTAssertThrowsError(try residency.reserveSlot(capacity: 1))
        slot.commit(ThreadId())
        XCTAssertTrue(isV2ResidentSessionSource(.subAgent(.review)))
        XCTAssertFalse(isV2ResidentSessionSource(.cli))
        XCTAssertEqual(defaultAgentNicknameList().first, "Euclid")
        XCTAssertEqual(defaultAgentNicknameList().last, "Jason")
        XCTAssertEqual(defaultAgentNicknameList().count, 101)
        XCTAssertEqual(agentNicknameCandidates().count, 101)
    }

    func testKeepAndRetainForkedHistory() {
        let user = RolloutItem.responseItem(
            ResponseItemEnvelope(
                item: .message(
                    id: nil,
                    role: "user",
                    content: [.inputText(text: "hi")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                )
            )
        )
        XCTAssertTrue(keepForkedRolloutItem(user, preserveContextBaselines: false))
        XCTAssertFalse(keepForkedRolloutItem(.retainedContext(.null), preserveContextBaselines: true))
        let turnContext = RolloutItem.turnContext(TurnContextItem(cwd: "/", model: "gpt"))
        XCTAssertTrue(keepForkedRolloutItem(turnContext, preserveContextBaselines: true))
        XCTAssertFalse(keepForkedRolloutItem(turnContext, preserveContextBaselines: false))

        var developer: ResponseItem = .message(
            id: nil,
            role: "developer",
            content: [
                .inputText(text: "<multi_agent_role>drop</multi_agent_role>"),
                .inputText(text: "keep this"),
            ],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
        XCTAssertTrue(retainForkedDeveloperMessage(&developer, usageHintTexts: []))
        guard case .message(_, _, let content, _, _) = developer else {
            return XCTFail("expected message")
        }
        XCTAssertEqual(content.count, 1)
        if case .inputText(let text) = content[0] {
            XCTAssertEqual(text, "keep this")
        } else {
            XCTFail("expected remaining input text")
        }
    }

    func testResolveUsageHintsPrefersConfiguredRoles() {
        let configured = resolveUsageHints(
            config: MultiAgentV2Config(
                rootAgentUsageHintText: "root hint",
                subagentUsageHintText: ""
            ),
            multiAgentMessages: ResolvedMultiAgentMessages(root: "catalog root", subagent: "catalog sub"),
            omitUpdatePlanInstructions: true
        )
        XCTAssertEqual(configured.root, .configured("root hint"))
        XCTAssertNil(configured.subagent)

        let composed = resolveUsageHints(
            config: MultiAgentV2Config(),
            multiAgentMessages: ResolvedMultiAgentMessages(
                root: "base",
                subagent: "child",
                rootCatalogOverride: true
            ),
            omitUpdatePlanInstructions: false
        )
        XCTAssertEqual(
            composed.root,
            .composed(
                base: "base",
                marked: true,
                omitUpdatePlanInstructions: false,
                maxConcurrency: 4,
                waitAgentEnabled: true,
                exposeModelOverrides: true
            )
        )
    }

    func testParentPathAndEnsureAgentKnown() throws {
        let child = try AgentPath(string: "/root/child")
        XCTAssertEqual(parentPath(of: child)?.asStr, "/root")
        XCTAssertNil(parentPath(of: .root()))
        let runtime = LocalAgentRuntime()
        XCTAssertThrowsError(try runtime.ensureAgentKnown(ThreadId()))
        let rootId = ThreadId()
        runtime.registerSessionRoot(currentThreadId: rootId, currentParentThreadId: nil)
        XCTAssertEqual(try runtime.ensureAgentKnown(rootId).agentId, rootId)
    }

    func testCombineSelectedCapabilityRootsRefreshesThreadOwnedMatch() throws {
        let cwd = try AbsolutePathBuf.currentDir()
        let cwdUri = PathUri.fromAbsPath(cwd)
        let persisted = SelectedCapabilityRoot(
            id: "root-1",
            location: .environment(environmentId: LOCAL_ENVIRONMENT_ID, path: cwdUri)
        )
        let refreshed = SelectedCapabilityRoot(
            id: "root-1",
            location: .environment(
                environmentId: LOCAL_ENVIRONMENT_ID,
                path: try PathUri.parse("file:///tmp/refreshed")
            )
        )
        let ownerOnly = SelectedCapabilityRoot(
            id: "root-2",
            location: .environment(environmentId: "remote", path: cwdUri)
        )
        let combined = combineSelectedCapabilityRoots(
            threadRoots: [persisted],
            sources: [
                (.thread, [refreshed]),
                (.owner, [ownerOnly]),
            ]
        )
        XCTAssertEqual(combined.map(\.id), ["root-1", "root-1", "root-2"])
        XCTAssertEqual(combined[0], refreshed)
    }

    func testValidateEnvironmentIdsAndResolveSelectionConfig() throws {
        let cwd = PathUri.fromAbsPath(try AbsolutePathBuf.currentDir())
        let local = TurnEnvironmentSelection(
            environmentId: LOCAL_ENVIRONMENT_ID,
            cwd: cwd,
            workspaceRoots: [cwd],
            config: .fromThread
        )
        let remote = TurnEnvironmentSelection(
            environmentId: "remote",
            cwd: cwd,
            workspaceRoots: [cwd],
            config: .fromThread
        )
        try validateEnvironmentIdsAndCwds(
            knownEnvironmentIds: [LOCAL_ENVIRONMENT_ID, "remote"],
            environments: [local, remote]
        )
        XCTAssertThrowsError(
            try validateEnvironmentIdsAndCwds(
                knownEnvironmentIds: [LOCAL_ENVIRONMENT_ID],
                environments: [local, remote]
            )
        )
        XCTAssertThrowsError(
            try validateEnvironmentIdsAndCwds(
                knownEnvironmentIds: [LOCAL_ENVIRONMENT_ID],
                environments: [local, local]
            )
        )

        let defaults = ThreadEnvironmentDefaults(
            common: threadEnvironmentConfig(),
            localWindowsSandboxType: .macosSeatbelt
        )
        let (resolved, origin) = resolveSelectionConfig(local, defaults: defaults)
        XCTAssertEqual(origin, .thread)
        guard case .ready(let config) = resolved.config else {
            return XCTFail("expected ready config")
        }
        XCTAssertEqual(config.windowsSandboxType, .macosSeatbelt)
        XCTAssertEqual(config.workspaceRoots, [cwd])
    }

    func testThreadEnvironmentsUpdateSelectionsAndSnapshot() throws {
        let cwd = PathUri.fromAbsPath(try AbsolutePathBuf.currentDir())
        let defaults = ThreadEnvironmentDefaults(
            common: threadEnvironmentConfig(),
            localWindowsSandboxType: .none
        )
        let environments = ThreadEnvironments(
            knownEnvironmentIds: [LOCAL_ENVIRONMENT_ID, "remote"],
            threadDefaults: defaults
        )
        environments.updateSelections([
            TurnEnvironmentSelection(
                environmentId: LOCAL_ENVIRONMENT_ID,
                cwd: cwd,
                workspaceRoots: [cwd],
                config: .fromThread
            ),
            TurnEnvironmentSelection(
                environmentId: "remote",
                cwd: cwd,
                workspaceRoots: [cwd],
                config: .pending
            ),
            TurnEnvironmentSelection(
                environmentId: LOCAL_ENVIRONMENT_ID,
                cwd: cwd,
                workspaceRoots: [cwd],
                config: .fromThread
            ),
        ])
        XCTAssertEqual(environments.selections().map(\.environmentId), [LOCAL_ENVIRONMENT_ID, "remote"])
        XCTAssertEqual(environments.selections()[0].config, .fromThread)
        let snapshot = environments.snapshot()
        XCTAssertEqual(snapshot.turnEnvironments().count, 1)
        XCTAssertEqual(snapshot.starting().count, 1)
        XCTAssertEqual(snapshot.primary()?.selection.environmentId, LOCAL_ENVIRONMENT_ID)
        XCTAssertEqual(snapshot.primaryWorkspaceRootUris(), [cwd])
        XCTAssertNotNil(snapshot.local())
        XCTAssertNil(snapshot.singleLocalEnvironment())
        XCTAssertFalse(
            snapshot.hasFullAccess(approvalPolicy: .never, threadProfile: .disabled)
        )
        XCTAssertTrue(
            TurnEnvironmentSnapshot().hasFullAccess(
                approvalPolicy: .never,
                threadProfile: .disabled
            )
        )

        var ownerConfig = threadEnvironmentConfig()
        ownerConfig.networkPolicy = EnvironmentNetworkPolicy()
        XCTAssertThrowsError(
            try validateEnvironmentConfig(
                TurnEnvironmentSelection(
                    environmentId: LOCAL_ENVIRONMENT_ID,
                    cwd: cwd,
                    workspaceRoots: [cwd],
                    config: .ready(ownerConfig)
                ),
                ownerConfig
            )
        )
        XCTAssertNoThrow(
            try validateEnvironmentConfig(
                TurnEnvironmentSelection(
                    environmentId: "remote",
                    cwd: cwd,
                    workspaceRoots: [cwd],
                    config: .ready(ownerConfig)
                ),
                ownerConfig
            )
        )
    }

    func testRenderInputPreviewAndSessionSourceAccessors() throws {
        let preview = renderInputPreview([
            .text(text: "hello", textElements: []),
            .localImage(path: "/tmp/a.png", detail: nil),
            .localAudio(path: "/tmp/a.wav"),
            .skill(name: "review", path: "/skills/review"),
            .mention(name: "mail", path: "plugin://mail"),
        ])
        XCTAssertEqual(
            preview,
            "hello\n[local_image:/tmp/a.png]\n[local_audio:/tmp/a.wav]\n[skill:$review](/skills/review)\n[mention:$mail](plugin://mail)"
        )

        let parent = ThreadId()
        let source = SessionSource.subAgent(
            .threadSpawn(
                parentThreadId: parent,
                depth: 1,
                agentPath: try AgentPath(string: "/root/ada"),
                agentNickname: "Ada",
                agentRole: "explorer"
            )
        )
        XCTAssertEqual(source.getNickname(), "Ada")
        XCTAssertEqual(source.getAgentRole(), "explorer")
        XCTAssertEqual(source.getAgentPath()?.asStr, "/root/ada")
        XCTAssertNil(SessionSource.cli.getNickname())
        XCTAssertNil(SessionSource.cli.getAgentRole())
    }

    func testPrepareMetadataListInspectAndChildPaths() async throws {
        let control = LocalAgentControl()
        let parent = ThreadId()
        let childReservation = try control.runtime.registry.reserveSpawnSlot(maxThreads: 4)
        let childPath = try AgentPath.root().join("ada")
        let (source, metadata) = try control.prepareThreadSpawn(
            reservation: childReservation,
            parentThreadId: parent,
            depth: 1,
            agentPath: childPath,
            agentRole: "explorer",
            preferredAgentNickname: "Ada"
        )
        XCTAssertEqual(metadata.agentNickname, "Ada")
        XCTAssertEqual(metadata.agentRole, "explorer")
        XCTAssertEqual(metadata.agentPath?.asStr, "/root/ada")
        XCTAssertNil(metadata.agentId)
        XCTAssertEqual(source.getNickname(), "Ada")
        XCTAssertEqual(source.getAgentRole(), "explorer")
        XCTAssertEqual(control.runtime.registry.agentIdForPath(.root()), parent)

        let childId = ThreadId()
        childReservation.commit(
            AgentMetadata(
                agentId: childId,
                agentPath: childPath,
                agentNickname: "Ada",
                agentRole: "explorer"
            )
        )

        let workerReservation = try control.runtime.registry.reserveSpawnSlot(maxThreads: 4)
        let workerPath = try childPath.join("worker")
        let workerMetadata = try control.prepareAgentMetadata(
            reservation: workerReservation,
            agentPath: workerPath,
            agentRole: "worker",
            preferredAgentNickname: "Euclid"
        )
        XCTAssertEqual(workerMetadata.agentNickname, "Euclid")
        let workerId = ThreadId()
        workerReservation.commit(
            AgentMetadata(
                agentId: workerId,
                agentPath: workerPath,
                agentNickname: "Euclid",
                agentRole: "worker"
            )
        )

        let listed = try await control.list(
            caller: parent,
            parent: nil,
            source: .cli,
            pathPrefix: nil
        )
        XCTAssertEqual(listed.map(\.threadId), [parent, childId, workerId])
        XCTAssertTrue(listed.allSatisfy { $0.status == .pendingInit })

        let filtered = try await control.list(
            caller: parent,
            parent: nil,
            source: .cli,
            pathPrefix: "ada"
        )
        XCTAssertEqual(filtered.map(\.threadId), [childId, workerId])

        do {
            _ = try await control.list(
                caller: parent,
                parent: nil,
                source: .cli,
                pathPrefix: "Ada"
            )
            XCTFail("expected invalid path prefix to throw")
        } catch is CodexErr {
        } catch {
            XCTFail("expected CodexErr, got \(error)")
        }

        let inspected = try await control.inspectAgent(childId)
        XCTAssertEqual(inspected.metadata().agentNickname, "Ada")
        XCTAssertNil(inspected.status())
        do {
            _ = try await control.inspectAgent(ThreadId())
            XCTFail("expected unknown agent to throw")
        } catch let err as CodexErr {
            if case .threadNotFound = err.detailsValue() {
            } else {
                XCTFail("expected threadNotFound, got \(err)")
            }
        } catch {
            XCTFail("expected CodexErr, got \(error)")
        }
        let knownStatus = await control.getStatus(childId)
        XCTAssertEqual(knownStatus, .notFound)
        let rootChildren = await control.childAgentPaths(parent: parent)
        XCTAssertEqual(rootChildren.map(\.asStr), ["/root/ada"])
        let adaChildren = await control.childAgentPaths(parent: childId)
        XCTAssertEqual(adaChildren.map(\.asStr), ["/root/ada/worker"])
        let missingChildren = await control.childAgentPaths(parent: ThreadId())
        XCTAssertTrue(missingChildren.isEmpty)
    }

    func testRegistrySpawnCloseAndEnsureChild() async throws {
        let control = LocalAgentControl()
        let parent = ThreadId()
        control.runtime.registry.registerRootThread(parent)
        let childPath = try AgentPath.root().join("ada")
        let source = SessionSource.subAgent(
            .threadSpawn(
                parentThreadId: parent,
                depth: 1,
                agentPath: childPath,
                agentNickname: "Ada",
                agentRole: "explorer"
            )
        )
        let (spawned, snapshot) = try await control.spawn(
            SpawnRequest(
                caller: parent,
                input: .userInput([.text(text: "hello", textElements: [])]),
                source: source,
                options: SpawnAgentOptions(parentThreadId: parent)
            )
        )
        XCTAssertEqual(spawned.status, .pendingInit)
        XCTAssertEqual(spawned.metadata.agentNickname, "Ada")
        XCTAssertEqual(spawned.metadata.agentPath?.asStr, "/root/ada")
        XCTAssertEqual(snapshot.sessionSource.getNickname(), "Ada")
        XCTAssertEqual(control.runtime.registry.agentIdForPath(childPath), spawned.threadId)

        try await control.ensureChildLoaded(parent: parent, child: spawned.threadId)
        do {
            try await control.ensureChildLoaded(parent: spawned.threadId, child: parent)
            XCTFail("expected parent/child mismatch to throw")
        } catch let err as CodexErr {
            if case .invalidRequest = err.detailsValue() {
            } else {
                XCTFail("expected invalidRequest, got \(err)")
            }
        }

        var subscription = try await control.subscribeStatus(agentId: spawned.threadId).makeAsyncIterator()
        let first = await subscription.next()
        XCTAssertEqual(first?.metadata().agentNickname, "Ada")
        let finished = await subscription.next()
        XCTAssertNil(finished)

        do {
            _ = try await control.send(
                SendRequest(
                    caller: parent,
                    target: .id(spawned.threadId),
                    input: .userInput([]),
                    startOptions: TurnStartOptions()
                )
            )
            XCTFail("expected empty send input to throw")
        } catch let err as CodexErr {
            if case .invalidRequest = err.detailsValue() {
            } else {
                XCTFail("expected invalidRequest, got \(err)")
            }
        }

        let queued = try await control.send(
            SendRequest(
                caller: parent,
                target: .id(spawned.threadId),
                input: .message(message: .plaintext("note"), mode: .queueOnly),
                startOptions: TurnStartOptions()
            )
        )
        XCTAssertEqual(queued.threadId, spawned.threadId)
        XCTAssertFalse(queued.submissionId.isEmpty)
        let queuedStatus = await control.getStatus(spawned.threadId)
        XCTAssertEqual(queuedStatus, .pendingInit)
        XCTAssertTrue(control.runtime.delivery.hasActivity(spawned.threadId))

        let triggered = try await control.send(
            SendRequest(
                caller: parent,
                target: .id(spawned.threadId),
                input: .userInput([.text(text: "go", textElements: [])]),
                startOptions: TurnStartOptions()
            )
        )
        XCTAssertFalse(triggered.submissionId.isEmpty)
        let running = await control.getStatus(spawned.threadId)
        XCTAssertEqual(running, .running)
        XCTAssertFalse(isFinal(running))

        let listed = try await control.list(
            caller: parent,
            parent: nil,
            source: source,
            pathPrefix: nil
        )
        XCTAssertEqual(listed.first { $0.threadId == spawned.threadId }?.status, .running)

        let inspected = try await control.inspectAgent(spawned.threadId)
        XCTAssertEqual(inspected.status(), .running)

        await control.turnFinished(
            outcome: AgentTurnOutcome(
                threadId: spawned.threadId,
                turnId: "turn-1",
                source: source,
                parentTurnId: "parent-turn",
                status: .completed("done")
            )
        )
        let completed = await control.getStatus(spawned.threadId)
        XCTAssertEqual(completed, .completed("done"))
        XCTAssertTrue(isFinal(completed))
        XCTAssertTrue(control.runtime.delivery.consumeActivity(parent))
        XCTAssertFalse(control.runtime.delivery.consumeActivity(parent))

        let resumed = try await control.resumeAgent(threadId: spawned.threadId, source: source)
        XCTAssertEqual(resumed.0.status, .completed("done"))

        let closed = try await control.closeAgent(spawned.threadId)
        XCTAssertEqual(closed.metadata().agentNickname, "Ada")
        XCTAssertEqual(closed.status(), .completed("done"))
        XCTAssertNil(control.runtime.registry.agentIdForPath(childPath))
        let missing = await control.getStatus(spawned.threadId)
        XCTAssertEqual(missing, .notFound)
    }

    func testInterruptDispatchValidatesV2Targets() async throws {
        let control = LocalAgentControl()
        let rootId = ThreadId()
        control.runtime.registry.registerRootThread(rootId)
        let reservation = try control.runtime.registry.reserveSpawnSlot(maxThreads: 2)
        let childPath = try AgentPath.root().join("ada")
        try reservation.reserveAgentPath(childPath)
        let childId = ThreadId()
        reservation.commit(AgentMetadata(agentId: childId, agentPath: childPath))

        XCTAssertTrue(
            SessionSource.subAgent(.review).isNonRootAgent()
        )
        XCTAssertTrue(SessionSource.internal(.guardian).isNonRootAgent())
        XCTAssertFalse(SessionSource.cli.isNonRootAgent())

        do {
            _ = try await control.interrupt(caller: rootId, target: .id(rootId), version: .v2)
            XCTFail("expected root interrupt to throw")
        } catch let err as CodexErr {
            XCTAssertTrue(String(describing: err).contains("root is not a spawned agent"))
        }
        do {
            _ = try await control.interrupt(caller: childId, target: .id(childId), version: .v2)
            XCTFail("expected self interrupt to throw")
        } catch let err as CodexErr {
            XCTAssertTrue(String(describing: err).contains("cannot interrupt itself"))
        }
        let interrupted = try await control.interrupt(caller: rootId, target: .id(childId), version: .v2)
        XCTAssertEqual(interrupted.metadata().agentPath?.asStr, childPath.asStr)
        let status = await control.getStatus(childId)
        XCTAssertEqual(status, .interrupted)
    }

    func testCollectAccessibleConnectorsAndCache() {
        let tools = [
            AccessibleConnectorTool(
                connectorId: "calendar",
                connectorName: "Google Calendar",
                pluginDisplayNames: ["Mail"]
            ),
            AccessibleConnectorTool(
                connectorId: "calendar",
                connectorDescription: "Calendar access",
                pluginDisplayNames: ["Notes"]
            ),
            AccessibleConnectorTool(connectorId: "drive", connectorName: "Drive"),
        ]
        let connectors = collectAccessibleConnectors(tools)
        XCTAssertEqual(connectors.map(\.id), ["drive", "calendar"])
        let calendar = connectors.first { $0.id == "calendar" }
        XCTAssertEqual(calendar?.name, "Google Calendar")
        XCTAssertEqual(calendar?.description, "Calendar access")
        XCTAssertEqual(calendar?.pluginDisplayNames, ["Mail", "Notes"])
        XCTAssertEqual(
            calendar?.installUrl,
            "https://chatgpt.com/apps/google-calendar/calendar"
        )
        XCTAssertEqual(calendar?.isAccessible, true)

        let key = AccessibleConnectorsCacheKey(chatgptBaseUrl: "https://chatgpt.com", accountId: "a1")
        writeCachedAccessibleConnectors(key, connectors: connectors)
        XCTAssertEqual(readCachedAccessibleConnectors(key)?.map(\.id), ["drive", "calendar"])
        XCTAssertNil(
            readCachedAccessibleConnectors(
                AccessibleConnectorsCacheKey(chatgptBaseUrl: "https://chatgpt.com", accountId: "other")
            )
        )
    }

    func testDiscoverableToolFilterAndListResult() {
        let plugin = DiscoverableTool.plugin(
            DiscoverablePluginInfo(id: "sample@shop", name: "Sample", hasSkills: true)
        )
        let connector = DiscoverableTool.connector(
            AppInfo(id: "calendar", name: "Calendar", isAccessible: true)
        )
        XCTAssertEqual(
            filterRequestPluginInstallDiscoverableToolsForClient(
                [plugin, connector],
                appServerClientName: TUI_CLIENT_NAME
            ).map { $0.id() },
            ["calendar"]
        )
        XCTAssertEqual(
            filterRequestPluginInstallDiscoverableToolsForClient(
                [plugin, connector],
                appServerClientName: nil
            ).count,
            2
        )
        let entries = collectRequestPluginInstallEntries([plugin, connector])
        let listed = listAvailablePluginsToInstallResult(
            entries + [
                RequestPluginInstallEntry(
                    id: "long@shop",
                    name: "Aaa",
                    description: String(repeating: "x", count: 241),
                    toolType: .plugin
                )
            ]
        )
        XCTAssertEqual(listed.tools.map(\.id), ["long@shop", "calendar", "sample@shop"])
        XCTAssertEqual(listed.tools[0].description?.count, 240)
    }

    func testResolveRequestedSpawnAgentModelOverrides() throws {
        let gpt = ModelPreset(
            id: "gpt",
            model: "gpt-5",
            displayName: "GPT",
            description: "d",
            defaultReasoningEffort: .medium,
            supportedReasoningEfforts: [ReasoningEffortPreset(effort: .medium, description: "")]
        )
        let resolved = try resolveRequestedSpawnAgentModelOverrides(
            availableModels: [gpt],
            multiAgentVersion: .v2,
            requestedModel: "gpt-5",
            requestedReasoningEffort: nil,
            fallbackModel: "parent",
            fallbackSupportedReasoningLevels: []
        )
        XCTAssertEqual(resolved.model, "gpt-5")
        XCTAssertEqual(resolved.reasoningEffort, .medium)
        XCTAssertThrowsError(
            try resolveRequestedSpawnAgentModelOverrides(
                availableModels: [gpt],
                multiAgentVersion: .v2,
                requestedModel: "gpt-5",
                requestedReasoningEffort: .high,
                fallbackModel: "parent",
                fallbackSupportedReasoningLevels: []
            )
        )
        XCTAssertEqual(
            resolveSpawnAgentServiceTier(requestedTier: "default") { _ in false },
            "default"
        )
        XCTAssertNil(resolveSpawnAgentServiceTier(requestedTier: "fast") { _ in false })
        XCTAssertEqual(resolveSpawnAgentServiceTier(requestedTier: "fast") { $0 == "fast" }, "fast")
    }

    func testWriteCuratedPluginFixture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-plugin-fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeOpenaiApiCuratedMarketplace(root: root, pluginNames: ["sample"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("plugins/sample/.codex-plugin/plugin.json").path
            )
        )
        let marketplace = try String(
            contentsOf: root.appendingPathComponent(".agents/plugins/api_marketplace.json"),
            encoding: .utf8
        )
        XCTAssertTrue(marketplace.contains(OPENAI_API_CURATED_MARKETPLACE_NAME))
    }
}
