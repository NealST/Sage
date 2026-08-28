//
//  ScheduleRunner+Script.swift
//  Sage
//

import Foundation

extension ScheduleRunner {
    nonisolated static func executeValidatedScript(
        _ record: ScheduleRecord,
        command: String,
        policy: PathGuard.Policy
    ) async throws -> ScheduleScriptOutcome {
        let cwd = try resolveWorkingDirectory(record.workingDirectory, policy: policy)
        let configuration = ExecutionSandboxConfiguration.shell(
            policy: policy,
            readAllowlist: [],
            allowsNetwork: false
        )
        let invocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-f", "-c", command],
            configuration: configuration,
            auditComponent: "scheduled_script"
        )
        let result = try await ProcessRunner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            currentDirectory: cwd,
            timeout: .seconds(30)
        )
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = output.isEmpty ? "(no output)" : String(output.prefix(240))
        if result.timedOut {
            return ScheduleScriptOutcome(
                excerpt: "Failed: timed out. \(excerpt)",
                exitCode: result.exitCode,
                failed: true
            )
        }
        if result.exitCode != 0 {
            return ScheduleScriptOutcome(
                excerpt: "Failed (exit \(result.exitCode)): \(excerpt)",
                exitCode: result.exitCode,
                failed: true
            )
        }
        return ScheduleScriptOutcome(excerpt: excerpt, exitCode: 0, failed: false)
    }

    /// Resolves a relative working directory inside the schedule’s PathGuard sandbox.
    nonisolated static func resolveWorkingDirectory(
        _ raw: String?,
        policy: PathGuard.Policy
    ) throws -> URL {
        let relative = ScheduleRecord.normalizedWorkingDirectory(raw)
        let candidate: URL
        if let relative {
            if relative.hasPrefix("/") || relative.hasPrefix("~") {
                candidate = URL(
                    fileURLWithPath: (relative as NSString).expandingTildeInPath
                )
            } else {
                candidate = policy.defaultWorkingDirectory.appendingPathComponent(relative)
            }
        } else {
            candidate = policy.defaultWorkingDirectory
        }
        let resolved = try PathGuard.resolveAllowed(candidate.path, policy: policy, access: .write)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ToolError.invalidArguments(
                "Working directory does not exist: \(PathGuard.displayPath(resolved.path, policy: policy))"
            )
        }
        return resolved
    }
}
