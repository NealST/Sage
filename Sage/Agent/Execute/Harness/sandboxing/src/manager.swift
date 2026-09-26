//
//  manager.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/manager.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Platform selection, MITM CA readable-root injection, compatibility
//  SandboxPolicy, and request types. Full `transform` wrapping of argv
//  (Linux landlock / Windows token) is macOS-only here: Seatbelt args are
//  produced via `createSeatbeltCommandArgs`.
//

import CodexProtocol
import CodexUtils
import Foundation

public enum SandboxablePreference: Equatable, Sendable {
    case auto
    case require
    case forbid
}

public func getPlatformSandbox(windowsSandboxEnabled: Bool) -> SandboxType? {
    _ = windowsSandboxEnabled
    return .macosSeatbelt
}

public func withManagedMitmCaReadableRoot(
    permissionProfile: PermissionProfile,
    managedMitmCaTrustBundlePath: AbsolutePathBuf?,
    sandboxPolicyCwd: String
) -> PermissionProfile {
    guard let managedMitmCaTrustBundlePath else { return permissionProfile }
    let (baseFileSystem, network) = permissionProfile.toRuntimePermissions()
    let fileSystem = baseFileSystem.withAdditionalReadableRoots(
        cwd: sandboxPolicyCwd,
        additionalReadableRoots: [managedMitmCaTrustBundlePath]
    )
    return PermissionProfile.fromRuntimePermissionsWithEnforcement(
        permissionProfile.enforcement(),
        fileSystem,
        network
    )
}

public struct SandboxCommand: Sendable {
    public var program: String
    public var args: [String]
    public var cwd: PathUri
    public var env: [String: String]
    public var managedNetwork: ManagedNetworkSandboxContext?
    public var additionalPermissions: AdditionalPermissionProfile?

    public init(
        program: String,
        args: [String],
        cwd: PathUri,
        env: [String: String],
        managedNetwork: ManagedNetworkSandboxContext? = nil,
        additionalPermissions: AdditionalPermissionProfile? = nil
    ) {
        self.program = program
        self.args = args
        self.cwd = cwd
        self.env = env
        self.managedNetwork = managedNetwork
        self.additionalPermissions = additionalPermissions
    }
}

public struct SandboxExecRequest: Sendable {
    public var command: [String]
    public var cwd: PathUri
    public var sandboxPolicyCwd: PathUri
    public var env: [String: String]
    public var network: NetworkProxy?
    public var networkEnvironmentId: String?
    public var sandbox: SandboxType
    public var windowsSandboxLevel: WindowsSandboxLevel
    public var permissionProfile: PermissionProfile
    public var arg0: String?

    public init(
        command: [String],
        cwd: PathUri,
        sandboxPolicyCwd: PathUri,
        env: [String: String],
        network: NetworkProxy? = nil,
        networkEnvironmentId: String? = nil,
        sandbox: SandboxType,
        windowsSandboxLevel: WindowsSandboxLevel,
        permissionProfile: PermissionProfile,
        arg0: String? = nil
    ) {
        self.command = command
        self.cwd = cwd
        self.sandboxPolicyCwd = sandboxPolicyCwd
        self.env = env
        self.network = network
        self.networkEnvironmentId = networkEnvironmentId
        self.sandbox = sandbox
        self.windowsSandboxLevel = windowsSandboxLevel
        self.permissionProfile = permissionProfile
        self.arg0 = arg0
    }
}

public struct SandboxTransformRequest: Sendable {
    public var command: SandboxCommand
    public var permissions: PermissionProfile
    public var sandbox: SandboxType
    public var enforceManagedNetwork: Bool
    public var environmentId: String?
    public var network: NetworkProxy?
    public var sandboxPolicyCwd: PathUri
    public var sandboxExe: String?
    public var useLegacyLandlock: Bool
    public var windowsSandboxLevel: WindowsSandboxLevel

    public init(
        command: SandboxCommand,
        permissions: PermissionProfile,
        sandbox: SandboxType,
        enforceManagedNetwork: Bool,
        environmentId: String? = nil,
        network: NetworkProxy? = nil,
        sandboxPolicyCwd: PathUri,
        sandboxExe: String? = nil,
        useLegacyLandlock: Bool = false,
        windowsSandboxLevel: WindowsSandboxLevel
    ) {
        self.command = command
        self.permissions = permissions
        self.sandbox = sandbox
        self.enforceManagedNetwork = enforceManagedNetwork
        self.environmentId = environmentId
        self.network = network
        self.sandboxPolicyCwd = sandboxPolicyCwd
        self.sandboxExe = sandboxExe
        self.useLegacyLandlock = useLegacyLandlock
        self.windowsSandboxLevel = windowsSandboxLevel
    }
}

public enum SandboxTransformError: Error, CustomStringConvertible {
    case invalidCommandCwd(cwd: PathUri, message: String)
    case invalidSandboxPolicyCwd(cwd: PathUri, message: String)
    case missingLinuxSandboxExecutable
    case windowsMxcPreparation(String)
    case environmentNetworkProxy(String)
    case seatbeltPreparation(String)

    public var description: String {
        switch self {
        case .invalidCommandCwd(let cwd, let message):
            return "command cwd URI `\(cwd)` is not valid on this host: \(message)"
        case .invalidSandboxPolicyCwd(let cwd, let message):
            return "sandbox policy cwd URI `\(cwd)` is not valid on this host: \(message)"
        case .missingLinuxSandboxExecutable:
            return "missing codex-linux-sandbox executable path"
        case .windowsMxcPreparation(let err):
            return "failed to prepare MXC sandbox: \(err)"
        case .environmentNetworkProxy(let err):
            return "failed to prepare environment network proxy: \(err)"
        case .seatbeltPreparation(let err):
            return "failed to prepare Seatbelt sandbox: \(err)"
        }
    }
}

public struct SandboxManager: Sendable {
    var seatbeltProfile: MacosSeatbeltProfile
    var allowedSymlinkedCodexHome: AbsolutePathBuf?

    public init() {
        seatbeltProfile = .process
        allowedSymlinkedCodexHome = nil
    }

    public static func forFileSystemHelpers() -> SandboxManager {
        var manager = SandboxManager()
        manager.seatbeltProfile = .fileSystemHelper
        return manager
    }

    public func withAllowedSymlinkedCodexHome(
        _ allowedSymlinkedCodexHome: AbsolutePathBuf?
    ) -> SandboxManager {
        var copy = self
        copy.allowedSymlinkedCodexHome = allowedSymlinkedCodexHome
        return copy
    }

    public func selectInitial(
        permissionProfile: PermissionProfile,
        pref: SandboxablePreference,
        windowsSandboxType: SandboxType,
        hasManagedNetworkRequirements: Bool
    ) -> SandboxType {
        if !shouldSandbox(
            permissionProfile,
            pref: pref,
            hasManagedNetworkRequirements: hasManagedNetworkRequirements
        ) {
            return .none
        }
        if windowsSandboxType == .windowsMxc {
            return .windowsMxc
        }
        return getPlatformSandbox(windowsSandboxEnabled: windowsSandboxType != .none) ?? .none
    }

    public func shouldSandbox(
        _ permissionProfile: PermissionProfile,
        pref: SandboxablePreference,
        hasManagedNetworkRequirements: Bool
    ) -> Bool {
        switch pref {
        case .forbid: return false
        case .require: return true
        case .auto:
            let (fileSystem, network) = permissionProfile.toRuntimePermissions()
            return shouldRequirePlatformSandbox(
                fileSystemPolicy: fileSystem,
                networkPolicy: network,
                hasManagedNetworkRequirements: hasManagedNetworkRequirements
            )
        }
    }

    public func transform(_ request: SandboxTransformRequest) throws -> SandboxExecRequest {
        let effective = effectivePermissionProfile(
            request.permissions,
            additionalPermissions: request.command.additionalPermissions
        )
        let (fileSystem, networkPolicy) = effective.toRuntimePermissions()
        let commandCwd: String
        do {
            commandCwd = try request.command.cwd.toAbsPath().asPath
        } catch {
            throw SandboxTransformError.invalidCommandCwd(
                cwd: request.command.cwd,
                message: String(describing: error)
            )
        }
        let policyCwd: String
        do {
            policyCwd = try request.sandboxPolicyCwd.toAbsPath().asPath
        } catch {
            throw SandboxTransformError.invalidSandboxPolicyCwd(
                cwd: request.sandboxPolicyCwd,
                message: String(describing: error)
            )
        }

        _ = commandCwd
        var command = [request.command.program] + request.command.args
        if request.sandbox == .macosSeatbelt,
           shouldRequirePlatformSandbox(
            fileSystemPolicy: fileSystem,
            networkPolicy: networkPolicy,
            hasManagedNetworkRequirements: request.enforceManagedNetwork
           ) {
            do {
                let seatbeltArgs = try createSeatbeltCommandArgsWithProfile(
                    CreateSeatbeltCommandArgsParams(
                        command: command,
                        fileSystemSandboxPolicy: fileSystem,
                        networkSandboxPolicy: networkPolicy,
                        sandboxPolicyCwd: policyCwd,
                        enforceManagedNetwork: request.enforceManagedNetwork,
                        managedNetwork: request.command.managedNetwork,
                        environmentId: request.environmentId,
                        network: request.network,
                        extraAllowUnixSockets: []
                    ),
                    profile: seatbeltProfile,
                    allowedSymlinkedCodexHome: allowedSymlinkedCodexHome
                )
                command = [MACOS_PATH_TO_SEATBELT_EXECUTABLE] + seatbeltArgs
            } catch {
                throw SandboxTransformError.seatbeltPreparation(String(describing: error))
            }
        }

        return SandboxExecRequest(
            command: command,
            cwd: request.command.cwd,
            sandboxPolicyCwd: request.sandboxPolicyCwd,
            env: request.command.env,
            network: request.network,
            networkEnvironmentId: request.environmentId,
            sandbox: request.sandbox,
            windowsSandboxLevel: request.windowsSandboxLevel,
            permissionProfile: effective,
            arg0: nil
        )
    }
}

public func compatibilitySandboxPolicyForPermissionProfile(
    _ permissions: PermissionProfile,
    cwd: String
) -> SandboxPolicy {
    if let policy = try? permissions.toLegacySandboxPolicy(cwd: cwd) {
        return policy
    }
    let (fileSystemPolicy, networkPolicy) = permissions.toRuntimePermissions()
    return compatibilityWorkspaceWritePolicy(fileSystemPolicy, networkPolicy, cwd: cwd)
}

private func compatibilityWorkspaceWritePolicy(
    _ fileSystemPolicy: FileSystemSandboxPolicy,
    _ networkPolicy: NetworkSandboxPolicy,
    cwd: String
) -> SandboxPolicy {
    let cwdAbs = try? AbsolutePathBuf.fromAbsolutePath(cwd)
    let writableRoots = fileSystemPolicy.getWritableRootsWithCwd(cwd)
        .map(\.root)
        .filter { root in cwdAbs.map { $0 != root } ?? true }
    let tmpdirWritable = ProcessInfo.processInfo.environment["TMPDIR"]
        .flatMap { $0.isEmpty ? nil : $0 }
        .flatMap { try? AbsolutePathBuf.fromAbsolutePath($0) }
        .map { fileSystemPolicy.canWriteLocalPathWithCwd($0.asPath, cwd: cwd) } ?? false
    let slashTmpWritable = FileManager.default.fileExists(atPath: "/tmp")
        && fileSystemPolicy.canWriteLocalPathWithCwd("/tmp", cwd: cwd)
    return .workspaceWrite(
        writableRoots: writableRoots,
        networkAccess: networkPolicy.isEnabled,
        excludeTmpdirEnvVar: !tmpdirWritable,
        excludeSlashTmp: !slashTmpWritable
    )
}
