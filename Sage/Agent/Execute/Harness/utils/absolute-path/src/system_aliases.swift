//
//  system_aliases.swift
//  CodexUtils
//
//  Port of codex-rs/utils/absolute-path/src/system_aliases.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Resolve a top-level system alias such as macOS `/tmp -> /private/tmp`.
//  Remaining components keep their logical spelling. `dunce::canonicalize`
//  is `realpath(3)` on Darwin (same as AbsolutePathBuf.canonicalize).
//

import Foundation

extension AbsolutePathBuf {
    /// Resolve a top-level system alias, such as macOS `/tmp -> /private/tmp`.
    /// All remaining components keep their logical spelling, even if they are
    /// symlinks or do not exist. Only call this on the host that owns the path.
    public func normalizeSystemAliases() throws -> AbsolutePathBuf {
        guard let topLevel = ancestors().first(where: { ancestor in
            ancestor.parent != nil && ancestor.parent?.parent == nil
        }) else {
            return self
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: topLevel.path)
            guard attrs[.type] as? FileAttributeType == .typeSymbolicLink else {
                return self
            }
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
            return self
        } catch {
            throw IOError.other(error.localizedDescription)
        }
        let canonicalTopLevel = try topLevel.canonicalize()
        let suffix: String
        if path == topLevel.path {
            suffix = ""
        } else if path.hasPrefix(topLevel.path + "/") {
            suffix = String(path.dropFirst(topLevel.path.count + 1))
        } else {
            throw IOError(kind: .other, "path is not under top-level alias \(topLevel.path)")
        }
        if suffix.isEmpty {
            return canonicalTopLevel
        }
        return try AbsolutePathBuf.fromAbsolutePath(canonicalTopLevel.path + "/" + suffix)
    }
}
