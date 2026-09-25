//
//  find_up.swift
//  FileSystem
//
//  Port of codex-rs/file-system/src/find_up.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Rust pipelines up to 256 metadata probes with `futures::stream::buffered`.
//  This port walks ancestors sequentially; buffered concurrency is an
//  optimization for remote filesystems and does not change first-match order.
//

import CodexUtils
import Foundation

// Keep enough ordinary metadata calls in flight to cover typical ancestor chains in one remote
// round trip, while leaving room for independent startup discovery to run at the same time.
let MAX_CONCURRENT_PROBES: Int = 256

/// Controls how an upward marker search handles metadata errors other than `NotFound`.
public enum FindUpErrorPolicy: Equatable, Sendable {
    /// Return the first error in lexical search order.
    case propagate
    /// Treat errors as missing markers and continue searching.
    case ignore
}

/// Finds the nearest ancestor containing one of the provided marker names.
///
/// Marker paths are probed in lexical order from `start` toward the filesystem root.
public func findNearestAncestorWithMarkers(
    fileSystem: any ExecutorFileSystem,
    start: PathUri,
    markers: [String],
    errorPolicy: FindUpErrorPolicy,
    sandbox: FileSystemSandboxContext?
) async throws -> PathUri? {
    try await findNearestAncestor(
        fileSystem: fileSystem,
        start: start,
        markers: markers,
        parent: { $0.parent() },
        markerPath: { ancestor, marker in
            do {
                return try ancestor.join(marker)
            } catch {
                throw IOError.invalidInput(String(describing: error))
            }
        },
        errorPolicy: errorPolicy,
        sandbox: sandbox
    )
}

/// Finds the nearest native ancestor containing one of the provided marker names.
///
/// Ancestors and marker paths remain native until each complete probe is converted to a URI. This
/// preserves paths that require an opaque `PathUri` fallback.
public func findNearestNativeAncestorWithMarkers(
    fileSystem: any ExecutorFileSystem,
    start: AbsolutePathBuf,
    markers: [String],
    errorPolicy: FindUpErrorPolicy,
    sandbox: FileSystemSandboxContext?
) async throws -> AbsolutePathBuf? {
    try await findNearestAncestor(
        fileSystem: fileSystem,
        start: start,
        markers: markers,
        parent: { $0.parent },
        markerPath: { ancestor, marker in
            PathUri.fromAbsPath(ancestor.join(marker))
        },
        errorPolicy: errorPolicy,
        sandbox: sandbox
    )
}

private func findNearestAncestor<P>(
    fileSystem: any ExecutorFileSystem,
    start: P,
    markers: [String],
    parent: (P) -> P?,
    markerPath: (P, String) throws -> PathUri,
    errorPolicy: FindUpErrorPolicy,
    sandbox: FileSystemSandboxContext?
) async throws -> P? {
    _ = MAX_CONCURRENT_PROBES
    var ancestor: P? = start
    while let current = ancestor {
        for marker in markers {
            let probe: PathUri
            do {
                probe = try markerPath(current, marker)
            } catch {
                throw error
            }
            do {
                _ = try await fileSystem.getMetadata(
                    probe,
                    options: .default,
                    sandbox: sandbox
                )
                return current
            } catch let error as IOError where error.kind == .notFound {
                continue
            } catch {
                switch errorPolicy {
                case .propagate:
                    throw error
                case .ignore:
                    continue
                }
            }
        }
        ancestor = parent(current)
    }
    return nil
}
