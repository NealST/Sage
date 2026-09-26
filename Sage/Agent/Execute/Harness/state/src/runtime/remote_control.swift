//
//  remote_control.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/remote_control.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SELECT / INSERT / UPDATE / DELETE SQL throws until a state pool exists.
//  Lookup-key helpers are implemented in memory.
//

import Foundation

let REMOTE_CONTROL_APP_SERVER_CLIENT_NAME_NONE = ""

/// Persisted remote-control server enrollment, including the lookup key.
public struct RemoteControlEnrollmentRecord: Equatable, Sendable {
    public var websocketUrl: String
    public var accountId: String
    public var appServerClientName: String?
    public var serverId: String
    public var environmentId: String
    public var serverName: String
    public var remoteControlEnabled: Bool?

    public init(
        websocketUrl: String,
        accountId: String,
        appServerClientName: String? = nil,
        serverId: String,
        environmentId: String,
        serverName: String,
        remoteControlEnabled: Bool? = nil
    ) {
        self.websocketUrl = websocketUrl
        self.accountId = accountId
        self.appServerClientName = appServerClientName
        self.serverId = serverId
        self.environmentId = environmentId
        self.serverName = serverName
        self.remoteControlEnabled = remoteControlEnabled
    }
}

func remoteControlAppServerClientNameKey(_ appServerClientName: String?) -> String {
    appServerClientName ?? REMOTE_CONTROL_APP_SERVER_CLIENT_NAME_NONE
}

func appServerClientNameFromKey(_ appServerClientName: String) -> String? {
    if appServerClientName.isEmpty {
        return nil
    }
    return appServerClientName
}

extension StateRuntime {
    public func getRemoteControlEnrollment(
        websocketUrl: String,
        accountId: String,
        appServerClientName: String?
    ) async throws -> RemoteControlEnrollmentRecord? {
        _ = remoteControlAppServerClientNameKey(appServerClientName)
        _ = websocketUrl
        _ = accountId
        throw StateRuntimeError.sqliteUnavailable("remote_control")
    }

    public func upsertRemoteControlEnrollment(
        _ enrollment: RemoteControlEnrollmentRecord
    ) async throws {
        _ = remoteControlAppServerClientNameKey(enrollment.appServerClientName)
        throw StateRuntimeError.sqliteUnavailable("remote_control")
    }

    public func setRemoteControlEnabled(
        websocketUrl: String,
        accountId: String,
        appServerClientName: String?,
        remoteControlEnabled: Bool
    ) async throws -> UInt64 {
        _ = remoteControlAppServerClientNameKey(appServerClientName)
        _ = websocketUrl
        _ = accountId
        _ = remoteControlEnabled
        throw StateRuntimeError.sqliteUnavailable("remote_control")
    }

    public func deleteRemoteControlEnrollment(
        websocketUrl: String,
        accountId: String,
        appServerClientName: String?
    ) async throws -> UInt64 {
        _ = remoteControlAppServerClientNameKey(appServerClientName)
        _ = websocketUrl
        _ = accountId
        throw StateRuntimeError.sqliteUnavailable("remote_control")
    }
}
