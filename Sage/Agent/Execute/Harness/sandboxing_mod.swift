//
//  sandboxing_mod.swift
//  Sage
//
//  Port of codex-rs/core/src/sandboxing/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: `sandboxing/mod.rs` → `sandboxing_mod.swift` so this core file is
//  not compiled under the excluded `sandboxing/` crate folder. Exec-server
//  env/snapshot fields are placeholders until that crate is ported.
//

import CodexProtocol
import CodexSandboxing
import CodexUtils
import FileSystem
import Foundation

public typealias SandboxPermissions = CodexProtocol.SandboxPermissions

struct ExecOptions {
    var expiration: ExecExpiration
    var capturePolicy: ExecCapturePolicy
}

struct ExecServerEnvConfig {
    var policy: ShellEnvironmentPolicy
    var localPolicyEnv: [String: String]
}

struct ShellSnapshotRequest: Equatable, Sendable {
    var scopeId: String
    var shellName: String
    var shellPath: String
}

struct RemoteNetworkProxyLaunchConfig: Equatable, Sendable {
    var environmentId: String?
}

public struct ExecRequest: Sendable {
    public var command: [String]
    public var cwd: PathUri
    public var env: [String: String]
    var execServerEnvConfig: ExecServerEnvConfig?
    var execServerShellSnapshot: ShellSnapshotRequest?
    public var network: NetworkProxy?
    public var networkEnvironmentId: String?
    public var expiration: ExecExpiration
    public var capturePolicy: ExecCapturePolicy
    public var sandbox: SandboxType
    public var windowsSandboxPolicyCwd: PathUri
    public var windowsSandboxWorkspaceRoots: [AbsolutePathBuf]
    public var windowsSandboxLevel: WindowsSandboxLevel
    public var permissionProfile: PermissionProfile
    var windowsSandboxFilesystemOverrides: WindowsSandboxFilesystemOverrides?
    public var arg0: String?
    var execServerSandbox: FileSystemSandboxContext?
    var execServerEnforceManagedNetwork: Bool
    var execServerManagedNetwork: ManagedNetworkSandboxContext?
    var execServerNetworkProxy: RemoteNetworkProxyLaunchConfig?

    public init(
        command: [String],
        cwd: AbsolutePathBuf,
        env: [String: String],
        network: NetworkProxy?,
        networkEnvironmentId: String?,
        expiration: ExecExpiration,
        capturePolicy: ExecCapturePolicy,
        sandbox: SandboxType,
        windowsSandboxWorkspaceRoots: [AbsolutePathBuf],
        windowsSandboxLevel: WindowsSandboxLevel,
        permissionProfile: PermissionProfile,
        arg0: String?
    ) {
        let cwdUri = PathUri.fromAbsPath(cwd)
        self.command = command
        self.cwd = cwdUri
        self.env = env
        self.execServerEnvConfig = nil
        self.execServerShellSnapshot = nil
        self.network = network
        self.networkEnvironmentId = networkEnvironmentId
        self.expiration = expiration
        self.capturePolicy = capturePolicy
        self.sandbox = sandbox
        self.windowsSandboxPolicyCwd = cwdUri
        self.windowsSandboxWorkspaceRoots = windowsSandboxWorkspaceRoots
        self.windowsSandboxLevel = windowsSandboxLevel
        self.permissionProfile = permissionProfile
        self.windowsSandboxFilesystemOverrides = nil
        self.arg0 = arg0
        self.execServerSandbox = nil
        self.execServerEnforceManagedNetwork = false
        self.execServerManagedNetwork = nil
        self.execServerNetworkProxy = nil
    }

    static func fromSandboxExecRequest(
        _ request: SandboxExecRequest,
        options: ExecOptions,
        windowsSandboxWorkspaceRoots: [AbsolutePathBuf]
    ) throws -> ExecRequest {
        var env = request.env
        if request.sandbox == .windowsRestrictedToken {
            throw CodexErr.unsupportedOperation(
                "Windows restricted-token filesystem overrides are unavailable on this platform"
            )
        }
        let networkSandboxPolicy = request.permissionProfile.networkSandboxPolicy()
        if !networkSandboxPolicy.isEnabled {
            env[CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR] = "1"
        }
        if request.sandbox == .macosSeatbelt {
            env[CODEX_SANDBOX_ENV_VAR] = "seatbelt"
        }
        var execRequest = ExecRequest(
            command: request.command,
            cwd: (try? request.cwd.toAbsPath()) ?? (try! AbsolutePathBuf.fromAbsolutePath("/")),
            env: env,
            network: request.network,
            networkEnvironmentId: request.networkEnvironmentId,
            expiration: options.expiration,
            capturePolicy: options.capturePolicy,
            sandbox: request.sandbox,
            windowsSandboxWorkspaceRoots: windowsSandboxWorkspaceRoots,
            windowsSandboxLevel: request.windowsSandboxLevel,
            permissionProfile: request.permissionProfile,
            arg0: request.arg0
        )
        execRequest.cwd = request.cwd
        execRequest.windowsSandboxPolicyCwd = request.sandboxPolicyCwd
        return execRequest
    }
}

func executeEnv(
    _ execRequest: ExecRequest,
    stdoutStream: StdoutStream?
) async -> CodexResult<ExecToolCallOutput> {
    await executeExecRequest(execRequest, stdoutStream: stdoutStream, afterSpawn: nil)
}

func executeExecRequestWithAfterSpawn(
    _ execRequest: ExecRequest,
    stdoutStream: StdoutStream?,
    afterSpawn: (() -> Void)?
) async -> CodexResult<ExecToolCallOutput> {
    await executeExecRequest(execRequest, stdoutStream: stdoutStream, afterSpawn: afterSpawn)
}
