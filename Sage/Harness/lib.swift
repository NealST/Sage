//
//  lib.swift
//  SageCore
//
//  Port of codex-rs/core/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Swift modules already expose per-file `public` types. This facade keeps
//  the deprecated ConversationManager aliases and documents the crate
//  surface. Realtime modules stay deferred. windows_sandbox is excluded.
//

import SageNetworkProxy
import SageTerminalDetection

@available(*, deprecated, renamed: "ThreadManager")
public typealias ConversationManager = ThreadManager
@available(*, deprecated, renamed: "NewThread")
public typealias NewConversation = NewThread
@available(*, deprecated, renamed: "SageThread")
public typealias SageConversation = SageThread

public typealias EnvironmentNetworkPolicy = SageNetworkProxy.EnvironmentNetworkPolicy
public typealias NetworkDomainPermission = SageNetworkProxy.NetworkDomainPermission
public typealias NetworkDomainPermissionEntry = SageNetworkProxy.NetworkDomainPermissionEntry
public typealias NetworkDomainPermissions = SageNetworkProxy.NetworkDomainPermissions
public typealias NetworkUnixSocketPermission = SageNetworkProxy.NetworkUnixSocketPermission
public typealias NetworkUnixSocketPermissions = SageNetworkProxy.NetworkUnixSocketPermissions

public func currentTerminalUserAgent() -> String {
    userAgent()
}
