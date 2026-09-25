//
//  git_discovery_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/git-discovery/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Bounded, shared Git-root discovery for optional metadata. Upstream uses
//  tokio primitives (Notify, Mutex, oneshot) and `std::thread::Builder`.
//  Sage uses Swift Concurrency (actor + TaskGroup) for the same bounded
//  concurrent probe semantics. The `codex_git_utils::get_git_repo_root`
//  call maps to a shell-out to `git rev-parse --show-toplevel`.
//
//  R4a: upstream `lib.rs` → `git_discovery_lib.swift` (basename dedup).
//

import Foundation

public let maxConcurrentRootProbesDefault = 8

/// Shares outstanding metadata probes by cwd and bounds probes across directories.
/// Entries survive caller cancellation but are not cached after filesystem work ends.
public actor GitRootDiscovery {
    private let capacity: Int
    private var inFlight: [String: Task<String?, Never>] = [:]
    private let findRoot: @Sendable (String) -> String?

    public init(
        capacity: Int = maxConcurrentRootProbesDefault,
        findRoot: @escaping @Sendable (String) -> String? = { getGitRepoRoot($0) }
    ) {
        self.capacity = capacity
        self.findRoot = findRoot
    }

    /// Joins the cwd's existing probe, waiting for capacity to start a detached
    /// worker when necessary. Dropping the Task cancels only the wait.
    public func discover(cwd: String) async -> String? {
        if let existingTask = inFlight[cwd] {
            return await existingTask.value
        }

        while inFlight.count >= capacity {
            guard let anyTask = inFlight.values.first else { break }
            _ = await anyTask.value
        }

        let findRootFn = findRoot
        let cwdCopy = cwd
        let task = Task<String?, Never>.detached {
            findRootFn(cwdCopy)
        }
        inFlight[cwd] = task

        let result = await task.value
        inFlight.removeValue(forKey: cwd)
        return result
    }
}

/// Default Git root finder: runs `git rev-parse --show-toplevel` in the
/// given directory. Returns `nil` if not inside a Git repo or on error.
public func getGitRepoRoot(_ cwd: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "--show-toplevel"]
    process.currentDirectoryURL = URL(fileURLWithPath: cwd)

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
