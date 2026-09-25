//
//  apply.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/apply.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Helpers for applying unified diffs using `/usr/bin/git`. Regex patterns
//  use `NSRegularExpression` in place of the `regex` crate.
//

import Foundation

/// Parameters for invoking `applyGitPatch`.
public struct ApplyGitRequest: Equatable, Sendable {
    public var cwd: String
    public var diff: String
    public var revert: Bool
    public var preflight: Bool

    public init(cwd: String, diff: String, revert: Bool, preflight: Bool) {
        self.cwd = cwd
        self.diff = diff
        self.revert = revert
        self.preflight = preflight
    }
}

/// Result of running `applyGitPatch`, including paths gleaned from stdout/stderr.
public struct ApplyGitResult: Equatable, Sendable {
    public var exitCode: Int32
    public var appliedPaths: [String]
    public var skippedPaths: [String]
    public var conflictedPaths: [String]
    public var stdout: String
    public var stderr: String
    public var cmdForLog: String

    public init(
        exitCode: Int32,
        appliedPaths: [String],
        skippedPaths: [String],
        conflictedPaths: [String],
        stdout: String,
        stderr: String,
        cmdForLog: String
    ) {
        self.exitCode = exitCode
        self.appliedPaths = appliedPaths
        self.skippedPaths = skippedPaths
        self.conflictedPaths = conflictedPaths
        self.stdout = stdout
        self.stderr = stderr
        self.cmdForLog = cmdForLog
    }
}

/// Apply a unified diff to the target repository by shelling out to `git apply`.
public func applyGitPatch(_ req: ApplyGitRequest) throws -> ApplyGitResult {
    let gitRoot = try resolveGitRoot(req.cwd)
    let (tmpdir, patchPath) = try writeTempPatch(req.diff)
    defer { try? FileManager.default.removeItem(at: tmpdir) }

    if req.revert && !req.preflight {
        try stagePaths(gitRoot: gitRoot, diff: req.diff)
    }

    var args = ["apply", "--3way"]
    if req.revert {
        args.append("-R")
    }

    var cfgParts: [String] = []
    if let cfg = ProcessInfo.processInfo.environment["CODEX_APPLY_GIT_CFG"] {
        for pair in cfg.split(separator: ",") {
            let p = pair.trimmingCharacters(in: .whitespaces)
            if p.isEmpty || !p.contains("=") { continue }
            cfgParts.append("-c")
            cfgParts.append(p)
        }
    }

    args.append(patchPath)

    if req.preflight {
        var checkArgs = ["apply", "--check"]
        if req.revert {
            checkArgs.append("-R")
        }
        checkArgs.append(patchPath)
        let rendered = renderCommandForLog(cwd: gitRoot, gitCfg: cfgParts, args: checkArgs)
        let (cCode, cOut, cErr) = try runGitApply(cwd: gitRoot, gitCfg: cfgParts, args: checkArgs)
        var (appliedPaths, skippedPaths, conflictedPaths) = parseGitApplyOutput(stdout: cOut, stderr: cErr)
        appliedPaths.sort()
        appliedPaths = uniqSorted(appliedPaths)
        skippedPaths.sort()
        skippedPaths = uniqSorted(skippedPaths)
        conflictedPaths.sort()
        conflictedPaths = uniqSorted(conflictedPaths)
        return ApplyGitResult(
            exitCode: cCode,
            appliedPaths: appliedPaths,
            skippedPaths: skippedPaths,
            conflictedPaths: conflictedPaths,
            stdout: cOut,
            stderr: cErr,
            cmdForLog: rendered
        )
    }

    let cmdForLog = renderCommandForLog(cwd: gitRoot, gitCfg: cfgParts, args: args)
    let (code, stdout, stderr) = try runGitApply(cwd: gitRoot, gitCfg: cfgParts, args: args)
    var (appliedPaths, skippedPaths, conflictedPaths) = parseGitApplyOutput(stdout: stdout, stderr: stderr)
    appliedPaths.sort()
    appliedPaths = uniqSorted(appliedPaths)
    skippedPaths.sort()
    skippedPaths = uniqSorted(skippedPaths)
    conflictedPaths.sort()
    conflictedPaths = uniqSorted(conflictedPaths)
    return ApplyGitResult(
        exitCode: code,
        appliedPaths: appliedPaths,
        skippedPaths: skippedPaths,
        conflictedPaths: conflictedPaths,
        stdout: stdout,
        stderr: stderr,
        cmdForLog: cmdForLog
    )
}

private func resolveGitRoot(_ cwd: String) throws -> String {
    let output = try runGitSync(
        arguments: ["-c", SAFE_BARE_REPOSITORY_CONFIG, "rev-parse", "--show-toplevel"],
        currentDirectory: cwd
    )
    if output.status != 0 {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EIO),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "not a git repository (exit \(output.status)): \(utf8Lossy(output.stderr))",
            ]
        )
    }
    return utf8Lossy(output.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func writeTempPatch(_ diff: String) throws -> (URL, String) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-git-apply-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("patch.diff")
    try diff.write(to: path, atomically: true, encoding: .utf8)
    return (dir, path.path)
}

private func runGitApply(
    cwd: String,
    gitCfg: [String],
    args: [String]
) throws -> (Int32, String, String) {
    var arguments = gitCfg
    arguments.append(contentsOf: ["-c", SAFE_BARE_REPOSITORY_CONFIG])
    arguments.append(contentsOf: args)
    let out = try runGitSync(arguments: arguments, currentDirectory: cwd)
    return (out.status, utf8Lossy(out.stdout), utf8Lossy(out.stderr))
}

private func quoteShell(_ s: String) -> String {
    let simple = s.unicodeScalars.allSatisfy { scalar in
        CharacterSet.alphanumerics.contains(scalar) || "-_.:/@%+".unicodeScalars.contains(scalar)
    }
    if simple {
        return s
    }
    return "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func renderCommandForLog(cwd: String, gitCfg: [String], args: [String]) -> String {
    var parts = ["git"]
    parts.append(contentsOf: gitCfg.map(quoteShell))
    parts.append(contentsOf: args.map(quoteShell))
    return "(cd \(quoteShell(cwd)) && \(parts.joined(separator: " ")))"
}

/// Collect every path referenced by the diff headers inside `diff --git` sections.
public func extractPathsFromPatch(_ diffText: String) -> [String] {
    var set = Set<String>()
    for rawLine in diffText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard let rest = line.stripPrefix("diff --git ") else { continue }
        guard let (a, b) = parseDiffGitPaths(rest) else { continue }
        if let a = normalizeDiffPath(a, prefix: "a/") {
            set.insert(a)
        }
        if let b = normalizeDiffPath(b, prefix: "b/") {
            set.insert(b)
        }
    }
    return set.sorted()
}

private func parseDiffGitPaths(_ line: String) -> (String, String)? {
    var chars = Array(line)
    var index = 0
    guard let first = readDiffGitToken(chars: &chars, index: &index),
          let second = readDiffGitToken(chars: &chars, index: &index)
    else {
        return nil
    }
    return (first, second)
}

private func readDiffGitToken(chars: inout [Character], index: inout Int) -> String? {
    while index < chars.count, chars[index].isWhitespace {
        index += 1
    }
    var quote: Character?
    if index < chars.count, chars[index] == "\"" || chars[index] == "'" {
        quote = chars[index]
        index += 1
    }
    var out = ""
    while index < chars.count {
        let c = chars[index]
        index += 1
        if let q = quote {
            if c == q { break }
            if c == "\\" {
                out.append("\\")
                if index < chars.count {
                    out.append(chars[index])
                    index += 1
                }
                continue
            }
        } else if c.isWhitespace {
            break
        }
        out.append(c)
    }
    if out.isEmpty && quote == nil {
        return nil
    }
    return quote == nil ? out : unescapeCString(out)
}

private func normalizeDiffPath(_ raw: String, prefix: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    if trimmed == "/dev/null" || trimmed == "\(prefix)dev/null" { return nil }
    let stripped = trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
    return stripped.isEmpty ? nil : stripped
}

func unescapeCString(_ input: String) -> String {
    var out = ""
    let chars = Array(input)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        i += 1
        if c != "\\" {
            out.append(c)
            continue
        }
        guard i < chars.count else {
            out.append("\\")
            break
        }
        let next = chars[i]
        i += 1
        switch next {
        case "n": out.append("\n")
        case "r": out.append("\r")
        case "t": out.append("\t")
        case "b": out.append("\u{0008}")
        case "f": out.append("\u{000C}")
        case "a": out.append("\u{0007}")
        case "v": out.append("\u{000B}")
        case "\\": out.append("\\")
        case "\"": out.append("\"")
        case "'": out.append("'")
        case "0"..."7":
            var value = Int(String(next), radix: 8) ?? 0
            for _ in 0..<2 {
                if i < chars.count, ("0"..."7").contains(chars[i]) {
                    value = value * 8 + (Int(String(chars[i]), radix: 8) ?? 0)
                    i += 1
                } else {
                    break
                }
            }
            if let scalar = UnicodeScalar(value) {
                out.append(Character(scalar))
            }
        default:
            out.append(next)
        }
    }
    return out
}

/// Stage only the files that actually exist on disk for the given diff.
public func stagePaths(gitRoot: String, diff: String) throws {
    let paths = extractPathsFromPatch(diff)
    var existing: [String] = []
    for p in paths {
        let joined = (gitRoot as NSString).appendingPathComponent(p)
        if (try? FileManager.default.attributesOfItem(atPath: joined)) != nil {
            existing.append(p)
        }
    }
    if existing.isEmpty { return }
    var arguments = ["-c", SAFE_BARE_REPOSITORY_CONFIG, "add", "--"]
    arguments.append(contentsOf: existing)
    _ = try runGitSync(arguments: arguments, currentDirectory: gitRoot)
}

/// Parse `git apply` output into applied/skipped/conflicted path groupings.
public func parseGitApplyOutput(stdout: String, stderr: String) -> ([String], [String], [String]) {
    let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    var applied = Set<String>()
    var skipped = Set<String>()
    var conflicted = Set<String>()
    var lastSeenPath: String?

    func add(_ set: inout Set<String>, _ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return }
        let first = trimmed.first
        let last = trimmed.last
        let unquoted: String
        if (first == "\"" || first == "'"), last == first, trimmed.count >= 2 {
            unquoted = unescapeCString(String(trimmed.dropFirst().dropLast()))
        } else {
            unquoted = trimmed
        }
        if !unquoted.isEmpty {
            set.insert(unquoted)
        }
    }

    for rawLine in combined.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }

        if let path = matchNamed(ApplyGitRegex.checkingPatch, line) {
            lastSeenPath = path
            continue
        }
        if let path = matchNamed(ApplyGitRegex.appliedClean, line) {
            add(&applied, path)
            if let p = applied.sorted().last {
                conflicted.remove(p)
                skipped.remove(p)
                lastSeenPath = p
            }
            continue
        }
        if let path = matchNamed(ApplyGitRegex.appliedConflicts, line) {
            add(&conflicted, path)
            if let p = conflicted.sorted().last {
                applied.remove(p)
                skipped.remove(p)
                lastSeenPath = p
            }
            continue
        }
        if let path = matchNamed(ApplyGitRegex.applyingWithRejects, line) {
            add(&conflicted, path)
            if let p = conflicted.sorted().last {
                applied.remove(p)
                skipped.remove(p)
                lastSeenPath = p
            }
            continue
        }
        if let path = matchNamed(ApplyGitRegex.unmergedLine, line) {
            add(&conflicted, path)
            if let p = conflicted.sorted().last {
                applied.remove(p)
                skipped.remove(p)
                lastSeenPath = p
            }
            continue
        }
        if ApplyGitRegex.patchFailed.isMatch(line) || ApplyGitRegex.doesNotApply.isMatch(line) {
            if let path = matchNamed(ApplyGitRegex.patchFailed, line) ?? matchNamed(ApplyGitRegex.doesNotApply, line) {
                add(&skipped, path)
                lastSeenPath = path
            }
            continue
        }
        if ApplyGitRegex.threeWayStart.isMatch(line) || ApplyGitRegex.fallbackDirect.isMatch(line) {
            continue
        }
        if ApplyGitRegex.threeWayFailed.isMatch(line) || ApplyGitRegex.lacksBlob.isMatch(line) {
            if let p = lastSeenPath {
                add(&skipped, p)
                applied.remove(p)
                conflicted.remove(p)
            }
            continue
        }
        if let path =
            matchNamed(ApplyGitRegex.indexMismatch, line)
            ?? matchNamed(ApplyGitRegex.notInIndex, line)
            ?? matchNamed(ApplyGitRegex.alreadyExistsWt, line)
            ?? matchNamed(ApplyGitRegex.fileExists, line)
            ?? matchNamed(ApplyGitRegex.renamedDeleted, line)
            ?? matchNamed(ApplyGitRegex.cannotApplyBinary, line)
            ?? matchNamed(ApplyGitRegex.binaryDoesNotApply, line)
            ?? matchNamed(ApplyGitRegex.binaryIncorrectResult, line)
            ?? matchNamed(ApplyGitRegex.cannotReadCurrent, line)
            ?? matchNamed(ApplyGitRegex.skippedPatch, line)
        {
            add(&skipped, path)
            if let p = skipped.sorted().last {
                applied.remove(p)
                conflicted.remove(p)
                lastSeenPath = p
            }
            continue
        }
        if let path = matchNamed(ApplyGitRegex.cannotMergeBinaryWarn, line) {
            add(&conflicted, path)
            if let p = conflicted.sorted().last {
                applied.remove(p)
                skipped.remove(p)
                lastSeenPath = p
            }
            continue
        }
    }

    applied.subtract(conflicted)
    skipped.subtract(conflicted)
    skipped.subtract(applied)
    return (applied.sorted(), skipped.sorted(), conflicted.sorted())
}

private func uniqSorted(_ values: [String]) -> [String] {
    var unique: [String] = []
    for value in values where unique.last != value {
        unique.append(value)
    }
    return unique
}

private enum ApplyGitRegex {
    static let appliedClean = regexCI("^Applied patch(?: to)?\\s+(?<path>.+?)\\s+cleanly\\.?$")
    static let appliedConflicts = regexCI("^Applied patch(?: to)?\\s+(?<path>.+?)\\s+with conflicts\\.?$")
    static let applyingWithRejects = regexCI("^Applying patch\\s+(?<path>.+?)\\s+with\\s+\\d+\\s+rejects?\\.{0,3}$")
    static let checkingPatch = regexCI("^Checking patch\\s+(?<path>.+?)\\.\\.\\.$")
    static let unmergedLine = regexCI("^U\\s+(?<path>.+)$")
    static let patchFailed = regexCI("^error:\\s+patch failed:\\s+(?<path>.+?)(?::\\d+)?(?:\\s|$)")
    static let doesNotApply = regexCI("^error:\\s+(?<path>.+?):\\s+patch does not apply$")
    static let threeWayStart = regexCI("^(?:Performing three-way merge|Falling back to three-way merge)\\.\\.\\.$")
    static let threeWayFailed = regexCI("^Failed to perform three-way merge\\.\\.\\.$")
    static let fallbackDirect = regexCI("^Falling back to direct application\\.\\.\\.$")
    static let lacksBlob = regexCI(
        "^(?:error: )?repository lacks the necessary blob to (?:perform|fall back on) 3-?way merge\\.?$"
    )
    static let indexMismatch = regexCI("^error:\\s+(?<path>.+?):\\s+does not match index\\b")
    static let notInIndex = regexCI("^error:\\s+(?<path>.+?):\\s+does not exist in index\\b")
    static let alreadyExistsWt = regexCI(
        "^error:\\s+(?<path>.+?)\\s+already exists in (?:the )?working directory\\b"
    )
    static let fileExists = regexCI("^error:\\s+patch failed:\\s+(?<path>.+?)\\s+File exists")
    static let renamedDeleted = regexCI("^error:\\s+path\\s+(?<path>.+?)\\s+has been renamed\\/deleted")
    static let cannotApplyBinary = regexCI(
        "^error:\\s+cannot apply binary patch to\\s+['\"]?(?<path>.+?)['\"]?\\s+without full index line$"
    )
    static let binaryDoesNotApply = regexCI(
        "^error:\\s+binary patch does not apply to\\s+['\"]?(?<path>.+?)['\"]?$"
    )
    static let binaryIncorrectResult = regexCI(
        "^error:\\s+binary patch to\\s+['\"]?(?<path>.+?)['\"]?\\s+creates incorrect result\\b"
    )
    static let cannotReadCurrent = regexCI(
        "^error:\\s+cannot read the current contents of\\s+['\"]?(?<path>.+?)['\"]?$"
    )
    static let skippedPatch = regexCI("^Skipped patch\\s+['\"]?(?<path>.+?)['\"]\\.$")
    static let cannotMergeBinaryWarn = regexCI(
        "^warning:\\s*Cannot merge binary files:\\s+(?<path>.+?)\\s+\\(ours\\s+vs\\.\\s+theirs\\)"
    )
}

private struct NamedRegex {
    let regex: NSRegularExpression

    func isMatch(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }

    func capture(_ line: String, name: String) -> String? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        let named = match.range(withName: name)
        guard named.location != NSNotFound, let swiftRange = Range(named, in: line) else { return nil }
        return String(line[swiftRange])
    }
}

private func regexCI(_ pattern: String) -> NamedRegex {
    do {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return NamedRegex(regex: regex)
    } catch {
        preconditionFailure("invalid regex: \(pattern): \(error)")
    }
}

private func matchNamed(_ regex: NamedRegex, _ line: String) -> String? {
    regex.capture(line, name: "path")
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
