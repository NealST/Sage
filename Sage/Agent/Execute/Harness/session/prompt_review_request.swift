//
//  prompt_review_request.swift
//  Sage
//
//  Port of codex-rs/prompts/src/review_request.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Prompt text matches rust. Base-branch resolution uses
//  `mergeBaseWithHead`; a missing merge base falls back to the
//  branch-name template. Git failures stay errors. The filename
//  avoids the app target's `guardian/review_request.swift` product.
//

import CodexGitUtils
import CodexProtocol
import Foundation

struct ResolvedReviewRequest: Equatable, Sendable {
    var target: ReviewTarget
    var prompt: String
    var userFacingHint: String
}

struct ReviewRequestError: Error, Equatable, CustomStringConvertible {
    var message: String
    var description: String { message }
}

let uncommittedReviewPrompt = "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."

func resolveReviewRequest(_ request: ReviewRequest, cwd: String) throws -> ResolvedReviewRequest {
    let mergeBase: String?
    if case .baseBranch(let branch) = request.target {
        mergeBase = try mergeBaseWithHead(repoPath: cwd, branch: branch)
    } else {
        mergeBase = nil
    }
    let prompt = try reviewPrompt(for: request.target, mergeBase: mergeBase)
    let hint = request.userFacingHint ?? userFacingReviewHint(request.target)
    return ResolvedReviewRequest(target: request.target, prompt: prompt, userFacingHint: hint)
}

func reviewPrompt(for target: ReviewTarget, mergeBase: String?) throws -> String {
    switch target {
    case .uncommittedChanges:
        return uncommittedReviewPrompt
    case .baseBranch(let branch):
        if let mergeBase, !mergeBase.isEmpty {
            return renderReviewPrompt(
                "Review the code changes against the base branch '{{base_branch}}'. The merge base commit for this comparison is {{merge_base_sha}}. Run `git diff {{merge_base_sha}}` to inspect the changes relative to {{base_branch}}. Provide prioritized, actionable findings.",
                ["base_branch": branch, "merge_base_sha": mergeBase]
            )
        }
        return renderReviewPrompt(
            "Review the code changes against the base branch '{{branch}}'. Start by finding the merge diff between the current branch and {{branch}}'s upstream e.g. (`git merge-base HEAD \"$(git rev-parse --abbrev-ref \"{{branch}}@{upstream}\")\"`), then run `git diff` against that SHA to see what changes we would merge into the {{branch}} branch. Provide prioritized, actionable findings.",
            ["branch": branch]
        )
    case .commit(let sha, let title):
        if let title {
            return renderReviewPrompt(
                "Review the code changes introduced by commit {{sha}} (\"{{title}}\"). Provide prioritized, actionable findings.",
                ["sha": sha, "title": title]
            )
        }
        return renderReviewPrompt(
            "Review the code changes introduced by commit {{sha}}. Provide prioritized, actionable findings.",
            ["sha": sha]
        )
    case .custom(let instructions):
        let prompt = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            throw ReviewRequestError(message: "Review prompt cannot be empty")
        }
        return prompt
    }
}

func userFacingReviewHint(_ target: ReviewTarget) -> String {
    switch target {
    case .uncommittedChanges:
        return "current changes"
    case .baseBranch(let branch):
        return "changes against '\(branch)'"
    case .commit(let sha, let title):
        let shortSha = String(sha.prefix(7))
        if let title {
            return "commit \(shortSha): \(title)"
        }
        return "commit \(shortSha)"
    case .custom(let instructions):
        return instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func renderReviewPrompt(_ template: String, _ variables: [String: String]) -> String {
    var text = template
    for (key, value) in variables {
        text = text.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    return text
}
