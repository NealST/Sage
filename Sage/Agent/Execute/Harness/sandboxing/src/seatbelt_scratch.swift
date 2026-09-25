//
//  seatbelt_scratch.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/seatbelt_scratch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Implicit /private/tmp and /private/var/tmp scratch grants, constrained
//  by unreadable roots and protected metadata.
//

import CodexProtocol
import CodexUtils
import Foundation

func scratchAccessRoots(
    policy: FileSystemSandboxPolicy,
    cwd: String,
    writableRoots: [WritableRoot]
) throws -> (reads: [SeatbeltAccessRoot], writes: [WritableRoot]) {
    let unreadable = policy.getUnreadableRootsWithCwd(cwd)
    var readOnly = policy.getReadableRootsWithCwd(cwd).filter { path in
        !policy.canWriteLocalPathWithCwd(path.asPath, cwd: cwd)
    }
    readOnly.append(contentsOf: unreadable)
    for root in writableRoots {
        readOnly.append(contentsOf: root.readOnlySubpaths)
        readOnly.append(contentsOf:
            protectedMetadataNamesForWritableRoot(policy: policy, writableRoot: root, cwd: cwd)
                .map { root.root.join($0) }
        )
    }

    let scratchPaths = try ["/private/tmp", "/private/var/tmp"].map {
        try AbsolutePathBuf.fromAbsolutePath($0)
    }
    var scratchPolicy = policy
    scratchPolicy.entries.append(contentsOf: try scratchPaths.map { path in
        FileSystemSandboxEntry.new(.path(path: try PathUri.fromHostNativePath(path.asPath)), .write)
    })
    let writes = scratchPolicy.getWritableRootsWithCwdPreservingMutablePaths(cwd)
        .filter { scratchPaths.contains($0.root) }
        .map { root -> WritableRoot in
            var root = root
            root.readOnlySubpaths.append(contentsOf: readOnly)
            return root
        }
    let reads = scratchPaths.map { root in
        SeatbeltAccessRoot(
            root: root,
            excludedSubpaths: unreadable,
            protectedMetadataNames: []
        )
    }
    return (reads, writes)
}
