//
//  discovery.swift
//  CodexAgentRoles
//
//  Port of codex-rs/agent-roles/src/discovery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexUtils
import FileSystem
import Foundation

public func collectAgentRoleFiles(
    fs: any ExecutorFileSystem,
    dir: AbsolutePathBuf
) async throws -> [AbsolutePathBuf] {
    var files: [AbsolutePathBuf] = []
    var dirs = [dir]
    while let directory = dirs.popLast() {
        let dirUri = PathUri.fromAbsPath(directory)
        let entries: [ReadDirectoryEntry]
        do {
            entries = try await fs.readDirectory(dirUri, sandbox: nil)
        } catch let error as IOError where error.kind == .notFound {
            continue
        } catch {
            throw error
        }

        for entry in entries {
            let path = directory.join(entry.fileName)
            if entry.isDirectory {
                dirs.append(path)
                continue
            }
            if entry.isFile && (path.path as NSString).pathExtension == "toml" {
                files.append(path)
            }
        }
    }

    files.sort()
    return files
}
