//
//  invocation.swift
//  ApplyPatch
//
//  Port of the Unix heredoc path in codex-rs/apply-patch/src/invocation.rs
//  (Apache-2.0). Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Pulls an apply_patch document out of a shell command so `apply_patch <<EOF`
//  is applied by this crate instead of /bin/zsh. PowerShell, cmd, and the
//  tree-sitter bash grammar stay out.
//

import Foundation

public enum ApplyPatchInvocation {
    /// Returns the `*** Begin Patch` … `*** End Patch` document when `command`
    /// is an apply_patch invocation. Other shell commands return nil.
    public static func patchDocument(inShellCommand command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        guard lowered.contains("apply_patch") || lowered.contains("applypatch") else {
            return nil
        }
        guard let begin = trimmed.range(of: "*** Begin Patch"),
              let end = trimmed.range(of: "*** End Patch", range: begin.lowerBound..<trimmed.endIndex)
        else {
            return nil
        }
        return String(trimmed[begin.lowerBound..<end.upperBound])
    }
}
