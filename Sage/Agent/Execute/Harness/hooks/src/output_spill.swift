//
//  output_spill.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/output_spill.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Token-budget spill is faithful. `formatted_truncate_text` uses the
//  existing byte-budget helper via `approxBytesForTokens`.
//

import CodexProtocol
import CodexUtils
import Foundation

let HOOK_OUTPUTS_DIR = "hook_outputs"
let DEFAULT_HOOK_OUTPUT_TOKEN_LIMIT: Int = 2_500

public struct AdditionalContextLimit: Equatable, Sendable {
    public var tokenLimit: Int

    public init(tokenLimit: Int) {
        self.tokenLimit = tokenLimit
    }

    public static func fromConfig(_ value: Int?) -> AdditionalContextLimit {
        AdditionalContextLimit(tokenLimit: value ?? DEFAULT_HOOK_OUTPUT_TOKEN_LIMIT)
    }

    public static let `default` = AdditionalContextLimit.fromConfig(nil)
}

public struct AdditionalContext: Equatable, Sendable {
    public var text: String
    public var limit: AdditionalContextLimit

    public init(text: String, limit: AdditionalContextLimit = .default) {
        self.text = text
        self.limit = limit
    }
}

public struct HookOutputSpiller: Sendable {
    public var outputDir: AbsolutePathBuf

    public init(threadId: ThreadId) {
        outputDir = AbsolutePathBuf.resolvePathAgainstBase(
            NSTemporaryDirectory(),
            basePath: "/"
        )
        .join(HOOK_OUTPUTS_DIR)
        .join(threadId.description)
    }

    public init(outputDir: AbsolutePathBuf) {
        self.outputDir = outputDir
    }

    /// Keeps hook text within the model-visible hook-output budget.
    public func maybeSpillText(_ text: String) async -> String {
        await maybeSpillText(text, limit: .default)
    }

    public func maybeSpillText(_ text: String, limit: AdditionalContextLimit) async -> String {
        let tokenLimit = limit.tokenLimit
        if tokenLimit == 0 || approxTokenCount(text) <= tokenLimit {
            return text
        }

        let path = outputDir.join("\(UUID().uuidString).txt")
        if let parent = path.parent {
            do {
                try FileManager.default.createDirectory(
                    atPath: parent.path,
                    withIntermediateDirectories: true
                )
            } catch {
                return formattedTruncateText(
                    content: text,
                    byteBudget: approxBytesForTokens(tokenLimit)
                )
            }
        }

        do {
            try text.write(toFile: path.path, atomically: true, encoding: .utf8)
        } catch {
            return formattedTruncateText(
                content: text,
                byteBudget: approxBytesForTokens(tokenLimit)
            )
        }
        return spilledHookOutputPreview(text, path: path, tokenLimit: tokenLimit)
    }

    public func maybeSpillAdditionalContexts(_ contexts: [AdditionalContext]) async -> [String] {
        var spilled: [String] = []
        spilled.reserveCapacity(contexts.count)
        for context in contexts {
            spilled.append(await maybeSpillText(context.text, limit: context.limit))
        }
        return spilled
    }

    public func maybeSpillPromptFragments(
        _ fragments: [HookPromptFragment]
    ) async -> [HookPromptFragment] {
        var spilled: [HookPromptFragment] = []
        spilled.reserveCapacity(fragments.count)
        for fragment in fragments {
            spilled.append(
                HookPromptFragment(
                    text: await maybeSpillText(fragment.text),
                    hookRunId: fragment.hookRunId
                )
            )
        }
        return spilled
    }
}

func spilledHookOutputPreview(_ text: String, path: AbsolutePathBuf, tokenLimit: Int) -> String {
    let footer = "\n\nFull hook output saved to: \(path.display)"
    let previewBudget = tokenLimit.saturatingSub(approxTokenCount(footer))
    return formattedTruncateText(
        content: text,
        byteBudget: approxBytesForTokens(previewBudget)
    ) + footer
}

private extension Int {
    func saturatingSub(_ other: Int) -> Int {
        self > other ? self - other : 0
    }
}
