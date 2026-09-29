//
//  lib.swift
//  CodexCore
//
//  Port of codex-rs/core/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Swift modules already expose per-file `public` types. This facade keeps
//  the deprecated ConversationManager aliases and documents the crate
//  surface. Realtime modules stay deferred. windows_sandbox is excluded.
//

import CodexNetworkProxy
import CodexTerminalDetection

@available(*, deprecated, renamed: "ThreadManager")
public typealias ConversationManager = ThreadManager
@available(*, deprecated, renamed: "NewThread")
public typealias NewConversation = NewThread
@available(*, deprecated, renamed: "CodexThread")
public typealias CodexConversation = CodexThread

public typealias EnvironmentNetworkPolicy = CodexNetworkProxy.EnvironmentNetworkPolicy
public typealias NetworkDomainPermission = CodexNetworkProxy.NetworkDomainPermission
public typealias NetworkDomainPermissionEntry = CodexNetworkProxy.NetworkDomainPermissionEntry
public typealias NetworkDomainPermissions = CodexNetworkProxy.NetworkDomainPermissions
public typealias NetworkUnixSocketPermission = CodexNetworkProxy.NetworkUnixSocketPermission
public typealias NetworkUnixSocketPermissions = CodexNetworkProxy.NetworkUnixSocketPermissions

public func currentTerminalUserAgent() -> String {
    userAgent()
}
