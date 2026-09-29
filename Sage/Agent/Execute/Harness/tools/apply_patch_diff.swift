//
//  apply_patch_diff.swift
//  Sage
//
//  Port of apply_patch argument-diff consumer in
//  codex-rs/core/src/tools/handlers/apply_patch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import ApplyPatch
import CodexProtocol
import Foundation

func createToolArgumentDiffConsumer(for item: ResponseItem) -> (callId: String, consumer: any ToolArgumentDiffConsumer)? {
    switch item {
    case .customToolCall(_, _, let callId, let name, _, _, _),
         .functionCall(_, let name, _, _, _, let callId, _):
        guard isApplyPatchToolName(name) else { return nil }
        return (callId, ApplyPatchArgumentDiffConsumer())
    default:
        return nil
    }
}

func isApplyPatchToolName(_ name: String) -> Bool {
    name == "apply_patch" || name.hasSuffix(".apply_patch")
}

final class ApplyPatchArgumentDiffConsumer: ToolArgumentDiffConsumer {
    private var parser = StreamingPatchParser()
    private var lastChanges: [String: FileChange] = [:]
    private var lastCallId: String?

    func consumeDiff(turn: TurnContext, callId: String, delta: String) -> EventMsg? {
        lastCallId = callId
        guard turn.config.features.enabled(.applyPatchStreamingEvents) else { return nil }
        let hunks = (try? parser.pushDelta(delta)) ?? []
        guard !hunks.isEmpty else { return nil }
        let changes = convertApplyPatchHunksToProtocol(hunks)
        lastChanges = changes
        return .patchApplyUpdated(PatchApplyUpdatedEvent(callId: callId, changes: changes))
    }

    func finish() throws -> EventMsg? {
        if let hunks = try? parser.finish(), !hunks.isEmpty {
            lastChanges = convertApplyPatchHunksToProtocol(hunks)
        }
        guard let callId = lastCallId, !lastChanges.isEmpty else { return nil }
        return .patchApplyUpdated(PatchApplyUpdatedEvent(callId: callId, changes: lastChanges))
    }
}

func convertApplyPatchHunksToProtocol(_ hunks: [Hunk]) -> [String: FileChange] {
    var changes: [String: FileChange] = [:]
    for hunk in hunks {
        switch hunk {
        case .addFile(let path, let contents):
            changes[path] = .add(content: contents)
        case .deleteFile(let path):
            changes[path] = .delete(content: "")
        case .updateFile(let path, let movePath, let chunks):
            changes[path] = .update(
                unifiedDiff: formatUpdateChunksForProgress(chunks),
                movePath: movePath
            )
        }
    }
    return changes
}

func formatUpdateChunksForProgress(_ chunks: [UpdateFileChunk]) -> String {
    var unifiedDiff = ""
    for chunk in chunks {
        if let context = chunk.changeContext {
            unifiedDiff += "@@ \(context)\n"
        } else {
            unifiedDiff += "@@\n"
        }
        for line in chunk.oldLines {
            unifiedDiff += "-\(line)\n"
        }
        for line in chunk.newLines {
            unifiedDiff += "+\(line)\n"
        }
        if chunk.isEndOfFile {
            unifiedDiff += "*** End of File\n"
        }
    }
    return unifiedDiff
}
