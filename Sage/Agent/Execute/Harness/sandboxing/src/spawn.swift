//
//  spawn.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/spawn.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request types are faithful. Process launch uses `utils/pty`
//  (`pty::spawn_process` / `pipe::spawn_process`). Windows sandbox spawn
//  remains excluded(platform).
//

import CodexProtocol
import CodexUtils
import Foundation

public struct WindowsSandboxSpawnRequest: Sendable {
    public var permissionProfile: PermissionProfile
    public var workspaceRoots: [AbsolutePathBuf]
    public var windowsSandboxLevel: WindowsSandboxLevel
    public var proxyEnforced: Bool
    public var networkProxyRestrictingSid: String?
    public var filesystemOverrides: WindowsSandboxFilesystemOverrides?

    public init(
        permissionProfile: PermissionProfile,
        workspaceRoots: [AbsolutePathBuf],
        windowsSandboxLevel: WindowsSandboxLevel,
        proxyEnforced: Bool,
        networkProxyRestrictingSid: String? = nil,
        filesystemOverrides: WindowsSandboxFilesystemOverrides? = nil
    ) {
        self.permissionProfile = permissionProfile
        self.workspaceRoots = workspaceRoots
        self.windowsSandboxLevel = windowsSandboxLevel
        self.proxyEnforced = proxyEnforced
        self.networkProxyRestrictingSid = networkProxyRestrictingSid
        self.filesystemOverrides = filesystemOverrides
    }
}

public struct WindowsSandboxFilesystemOverrides: Equatable, Sendable {
    public var readRootsOverride: [AbsolutePathBuf]?
    public var readRootsIncludePlatformDefaults: Bool
    public var writeRootsOverride: [AbsolutePathBuf]?
    public var additionalDenyReadPaths: [AbsolutePathBuf]
    public var additionalDenyWritePaths: [AbsolutePathBuf]

    public init(
        readRootsOverride: [AbsolutePathBuf]? = nil,
        readRootsIncludePlatformDefaults: Bool = false,
        writeRootsOverride: [AbsolutePathBuf]? = nil,
        additionalDenyReadPaths: [AbsolutePathBuf] = [],
        additionalDenyWritePaths: [AbsolutePathBuf] = []
    ) {
        self.readRootsOverride = readRootsOverride
        self.readRootsIncludePlatformDefaults = readRootsIncludePlatformDefaults
        self.writeRootsOverride = writeRootsOverride
        self.additionalDenyReadPaths = additionalDenyReadPaths
        self.additionalDenyWritePaths = additionalDenyWritePaths
    }
}

public struct SpawnRequest: Sendable {
    public var command: [String]
    public var cwd: String
    public var env: [String: String]
    public var arg0: String?
    public var sandbox: SandboxType
    public var windowsSandbox: WindowsSandboxSpawnRequest?
    public var tty: Bool
    public var stdinOpen: Bool

    public init(
        command: [String],
        cwd: String,
        env: [String: String],
        arg0: String? = nil,
        sandbox: SandboxType,
        windowsSandbox: WindowsSandboxSpawnRequest? = nil,
        tty: Bool,
        stdinOpen: Bool
    ) {
        self.command = command
        self.cwd = cwd
        self.env = env
        self.arg0 = arg0
        self.sandbox = sandbox
        self.windowsSandbox = windowsSandbox
        self.tty = tty
        self.stdinOpen = stdinOpen
    }
}

public func spawnProcess(_ request: SpawnRequest) async throws -> SpawnedProcess {
    guard let program = request.command.first else {
        throw CodexErr.io("command args are empty")
    }
    let args = Array(request.command.dropFirst())
    if request.sandbox == .windowsRestrictedToken {
        throw CodexErr.unsupportedOperation(
            "Windows sandbox process spawn is unavailable on this platform"
        )
    }
    if request.tty {
        return try await spawnPtyProcess(
            program: program,
            args: args,
            cwd: request.cwd,
            env: request.env,
            arg0: request.arg0,
            size: TerminalSize(),
            inheritedFds: .attached([])
        )
    }
    if request.stdinOpen {
        return try await spawnPipeProcess(
            program: program,
            args: args,
            cwd: request.cwd,
            env: request.env,
            arg0: request.arg0
        )
    }
    return try await spawnPipeProcessNoStdin(
        program: program,
        args: args,
        cwd: request.cwd,
        env: request.env,
        arg0: request.arg0
    )
}
