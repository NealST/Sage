//
//  shell_snapshot_sandbox.swift
//  Sage
//
//  Port of codex-rs/core/src/shell_snapshot_sandbox.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `SandboxAttempt` lives in Phase 4 tools, so this struct is constructed
//  from sandbox fields directly. Network-proxy prepare-for-environment is
//  the inlined CodexSandboxing subset (env overlay only).
//

import CodexAsyncUtils
import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

struct ShellSnapshotSandbox: Equatable, Sendable {
    var sandbox: SandboxType
    var sandboxRequested: Bool
    var permissions: PermissionProfile
    var enforceManagedNetwork: Bool
    var sandboxPolicyCwd: PathUri
    var workspaceRoots: [PathUri]
    var sandboxExe: String?
    var useLegacyLandlock: Bool
    var windowsSandboxLevel: WindowsSandboxLevel
    var network: NetworkProxy?
    var environmentId: String
    var additionalPermissions: AdditionalPermissionProfile?
}

func snapshotReadPermissions(
    snapshotPath: AbsolutePathBuf,
    permissions: PermissionProfile,
    sandboxCwd: PathUri
) -> AdditionalPermissionProfile? {
    if let cwd = try? sandboxCwd.toAbsPath(),
       permissions
        .fileSystemSandboxPolicy()
        .canReadLocalPathWithCwd(snapshotPath.asPath, cwd: cwd.asPath) {
        return nil
    }
    return AdditionalPermissionProfile(
        network: nil,
        fileSystem: FileSystemPermissions.fromReadWriteRoots(
            read: [snapshotPath],
            write: nil
        )
    )
}

extension ShellSnapshotSandbox {
    func cacheKey() throws -> String {
        let networkPart: String
        if let network {
            let keys = network.environmentEnv.keys.sorted().map {
                "\($0)=\(network.environmentEnv[$0] ?? "")"
            }
            networkPart = keys.joined(separator: ",")
        } else {
            networkPart = ""
        }
        return [
            sandbox.metricTag,
            sandboxRequested ? "1" : "0",
            String(describing: permissions),
            enforceManagedNetwork ? "1" : "0",
            sandboxPolicyCwd.toPathBuf(),
            workspaceRoots.map { $0.toPathBuf() }.joined(separator: ","),
            sandboxExe ?? "",
            useLegacyLandlock ? "1" : "0",
            String(describing: windowsSandboxLevel),
            networkPart,
            environmentId,
            String(describing: additionalPermissions),
        ].joined(separator: "|")
    }

    func run(
        args: [String],
        cwd: AbsolutePathBuf,
        env: [String: String],
        snapshotTimeout: Duration,
        shellName: String,
        snapshotReadPath: AbsolutePathBuf?
    ) async throws -> String {
        if sandboxRequested && sandbox == .none {
            throw CodexErr.fatal("shell snapshot sandbox cannot be enforced on this host")
        }

        var env = env
        if let network {
            try network.applyToEnvForOptionalEnvironment(&env, environmentId: environmentId)
        }
        guard let program = args.first else {
            throw CodexErr.fatal("shell snapshot command is empty")
        }
        let snapshotPermissions = snapshotReadPath.flatMap { path in
            snapshotReadPermissions(
                snapshotPath: path,
                permissions: permissions.materializeProjectRootsWithPathUris(workspaceRoots),
                sandboxCwd: sandboxPolicyCwd
            )
        }
        let mergedAdditional = mergePermissionProfiles(
            base: additionalPermissions,
            permissions: snapshotPermissions
        )
        let manager = SandboxManager()
        let transformed = try manager.transform(
            SandboxTransformRequest(
                command: SandboxCommand(
                    program: program,
                    args: Array(args.dropFirst()),
                    cwd: PathUri.fromAbsPath(cwd),
                    env: env,
                    additionalPermissions: mergedAdditional
                ),
                permissions: permissions,
                sandbox: sandbox,
                enforceManagedNetwork: enforceManagedNetwork,
                environmentId: environmentId,
                network: network,
                sandboxPolicyCwd: sandboxPolicyCwd,
                sandboxExe: sandboxExe,
                useLegacyLandlock: useLegacyLandlock,
                windowsSandboxLevel: windowsSandboxLevel
            )
        )
        let resolvedWorkspaceRoots = try workspaceRoots.map { try $0.toAbsPath() }
        let cancellation = CancellationToken()
        let expiration = ExecExpiration.timeoutOrCancellation(
            timeout: snapshotTimeout,
            cancellation: cancellation
        )
        let request = try ExecRequest.fromSandboxExecRequest(
            transformed,
            options: ExecOptions(
                expiration: expiration,
                capturePolicy: .sensitiveFullBuffer
            ),
            windowsSandboxWorkspaceRoots: resolvedWorkspaceRoots
        )
        let result = await executeEnv(request, stdoutStream: nil)
        switch result {
        case .success(let output):
            if output.exitCode != 0 {
                throw CodexErr.fatal("Snapshot command exited with status \(output.exitCode)")
            }
            return output.stdout.text
        case .failure(let error):
            switch error.details {
            case .sandbox(.denied(let output, _)):
                throw CodexErr.fatal(
                    "Snapshot command was denied by sandbox with status \(output.exitCode)"
                )
            case .sandbox(.timeout):
                throw CodexErr.fatal("Snapshot command timed out")
            default:
                throw CodexErr.fatal("Failed to execute sandboxed \(shellName): \(error)")
            }
        }
    }
}
