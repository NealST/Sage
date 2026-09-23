//
//  apply_patch.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/apply_patch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  JSON-tool entry for Execute. Parses the Codex patch language, PathGuards
//  every path, then hands the hunks to ToolsRuntimes.ApplyPatchRuntime.
//

import ApplyPatch
import Foundation
import ToolsRuntimes

nonisolated struct ApplyPatchHandler: AgentTool {
    let definition = ApplyPatchSpec.definition

    private struct Args: Decodable {
        let input: String?
        let patch: String?
    }

    func call(argumentsJSON: String) throws -> String {
        let patch = try Self.extractPatch(from: argumentsJSON)
        let parsed: ApplyPatchArgs
        do {
            parsed = try parsePatch(patch)
        } catch let error as ParseError {
            throw ToolError.invalidArguments(Self.describeParseError(error))
        }

        let cwd = PathGuard.policy.defaultWorkingDirectory
        try Self.assertPathsAllowed(parsed.hunks, cwd: cwd)

        let result: (delta: AppliedPatchDelta, summary: String)
        do {
            result = try ApplyPatchRuntime.run(
                ApplyPatchRequest(
                    cwd: cwd,
                    hunks: parsed.hunks,
                    options: ApplyPatchOptions(
                        updateFileMode: .preserveLineEndings,
                        followSymlinks: true
                    )
                )
            )
        } catch let failure as ApplyPatchFailure {
            throw ToolError.operationFailed(failure.error.localizedDescription)
        } catch {
            throw ToolError.operationFailed(error.localizedDescription)
        }

        return Self.encodeResult(summary: result.summary, delta: result.delta)
    }

    static func encodeApplied(summary: String, delta: AppliedPatchDelta) -> String {
        encodeResult(summary: summary, delta: delta)
    }

    static func extractPatch(from argumentsJSON: String) throws -> String {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(BEGIN_PATCH_MARKER) || trimmed.hasPrefix("<<") {
            return trimmed
        }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        if let input = args.input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
            return input
        }
        if let patch = args.patch?.trimmingCharacters(in: .whitespacesAndNewlines), !patch.isEmpty {
            return patch
        }
        throw ToolError.invalidArguments("apply_patch requires an `input` patch document.")
    }

    static func hunkPaths(in patch: String, cwd: URL) -> [URL] {
        guard let parsed = try? parsePatch(patch) else { return [] }
        return parsed.hunks.flatMap { hunk -> [URL] in
            var urls = [hunk.resolveSourcePath(cwd: cwd)]
            if case .updateFile(_, let movePath, _) = hunk, let movePath {
                urls.append(ApplyPatchPaths.resolve(movePath, cwd: cwd))
            }
            return urls
        }
    }

    private static func assertPathsAllowed(_ hunks: [Hunk], cwd: URL) throws {
        for hunk in hunks {
            _ = try PathGuard.resolveAllowed(hunk.resolveSourcePath(cwd: cwd).path, access: .write)
            if case .updateFile(_, let movePath, _) = hunk, let movePath {
                _ = try PathGuard.resolveAllowed(
                    ApplyPatchPaths.resolve(movePath, cwd: cwd).path,
                    access: .write
                )
            }
        }
    }

    static func describeParseError(_ error: ParseError) -> String {
        switch error {
        case .invalidPatch(let message):
            return "Invalid patch: \(message)"
        case .invalidHunk(let message, let lineNumber):
            return "Invalid patch hunk on line \(lineNumber): \(message)"
        }
    }

    private static func encodeResult(summary: String, delta: AppliedPatchDelta) -> String {
        let payloads = delta.changes.compactMap(payload(from:))
        return WriteFileResultCodec.embed(summary: summary.trimmingCharacters(in: .newlines), payloads: payloads)
    }

    private static func payload(from change: AppliedPatchChange) -> WriteFileDiffPayload? {
        let path = PathGuard.displayPath(change.path.path)
        switch change.kind {
        case .add(let content, let overwritten):
            let stats = LineDiff.stats(before: overwritten ?? "", after: content)
            return WriteFileDiffPayload(
                path: path,
                created: overwritten == nil,
                before: overwritten,
                after: content,
                insertions: stats.insertions,
                deletions: stats.deletions,
                truncated: false
            )
        case .delete(let content):
            return WriteFileDiffPayload(
                path: path,
                created: false,
                before: content,
                after: "",
                insertions: 0,
                deletions: LineDiff.stats(before: content, after: "").deletions,
                truncated: false,
                previousPath: nil
            )
        case .update(let movePath, let oldContent, _, let newContent):
            let dest = movePath.map { PathGuard.displayPath($0.path) } ?? path
            let stats = LineDiff.stats(before: oldContent, after: newContent)
            return WriteFileDiffPayload(
                path: dest,
                created: false,
                before: oldContent,
                after: newContent,
                insertions: stats.insertions,
                deletions: stats.deletions,
                truncated: false,
                previousPath: movePath == nil ? nil : path
            )
        }
    }
}

struct ApplyPatchExecRequest: Sendable {
    var patch: String
    var hunks: [Hunk]
    var cwd: URL
    var paths: [URL]
}

struct ApplyPatchToolRuntime: ToolRuntime {
    func sandboxPreference() -> SandboxablePreference { .auto }

    func escalateOnFailure() -> Bool { true }

    func execApprovalRequirement(_ request: ApplyPatchExecRequest) -> ExecApprovalRequirement? {
        let protected = request.paths.contains(where: WorkspaceMetadataPaths.isProtected)
        return protected ? .needsApproval(reason: "Patch writes .git, .sage, or .agents.") : .skip(bypassSandbox: false)
    }

    func approvalAction(_ request: ApplyPatchExecRequest, callID: String) -> ApprovalAction {
        .applyPatch(id: callID, cwd: request.cwd, files: request.paths, patch: request.patch)
    }

    func sandboxCwd(_ request: ApplyPatchExecRequest) -> URL? {
        request.cwd
    }

    func run(
        _ request: ApplyPatchExecRequest,
        attempt: SandboxAttempt,
        ctx: ToolCtx
    ) async throws -> String {
        try ApplyPatchToolRuntime.applyEmbedded(
            patch: request.patch,
            cwd: request.cwd,
            attempt: attempt,
            policy: ctx.pathGuardPolicy
        )
    }

    static func execute(_ invocation: ToolInvocationRequest) async throws -> String {
        let patch = try ApplyPatchHandler.extractPatch(from: invocation.argumentsJSON)
        let parsed: ApplyPatchArgs
        do {
            parsed = try parsePatch(patch)
        } catch let error as ParseError {
            throw ToolError.invalidArguments(ApplyPatchHandler.describeParseError(error))
        }
        let cwd = invocation.pathGuardPolicy.defaultWorkingDirectory
        let paths = ApplyPatchHandler.hunkPaths(in: patch, cwd: cwd)
        for path in paths {
            _ = try PathGuard.resolveAllowed(path.path, policy: invocation.pathGuardPolicy, access: .write)
        }
        let request = ApplyPatchExecRequest(patch: patch, hunks: parsed.hunks, cwd: cwd, paths: paths)
        let output = try await ToolOrchestrator().run(
            tool: ApplyPatchToolRuntime(),
            request: request,
            ctx: ToolCtx.sage(request: invocation),
            approver: InvocationApprover(
                authorization: invocation.authorization,
                evidence: invocation.authorizationEvidence
            )
        )
        return output
    }

    static func applyEmbedded(
        patch: String,
        cwd: URL,
        attempt: SandboxAttempt,
        policy: PathGuard.Policy
    ) throws -> String {
        try PathGuard.$policy.withValue(policy) {
            let parsed = try parsePatch(patch)
            let paths = parsed.hunks.flatMap { hunk -> [URL] in
                var urls = [hunk.resolveSourcePath(cwd: cwd)]
                if case .updateFile(_, let movePath, _) = hunk, let movePath {
                    urls.append(ApplyPatchPaths.resolve(movePath, cwd: cwd))
                }
                return urls
            }
            if attempt.sandbox == .seatbelt, paths.contains(where: WorkspaceMetadataPaths.isProtected) {
                let path = paths.first(where: WorkspaceMetadataPaths.isProtected)?.path ?? cwd.path
                throw HarnessToolError.sandboxDenied(
                    output: "[exit 1]\nOperation not permitted: \(path)"
                )
            }
            for path in paths {
                _ = try PathGuard.resolveAllowed(path.path, policy: policy, access: .write)
            }
            let result = try ApplyPatchRuntime.run(
                ApplyPatchRequest(
                    cwd: cwd,
                    hunks: parsed.hunks,
                    options: ApplyPatchOptions(updateFileMode: .preserveLineEndings, followSymlinks: true)
                )
            )
            return ApplyPatchHandler.encodeApplied(summary: result.summary, delta: result.delta)
        }
    }
}

enum WorkspaceMetadataPaths {
    static func isProtected(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { component in
            component == ".git" || component == ".sage" || component == ".agents"
        }
    }
}
