//
//  installation_id.swift
//  CodexCore
//
//  Port of codex-rs/core/src/installation_id.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `std::fs::File::lock` maps to `flock(2)` via `fcntl`. File I/O is
//  offloaded with `Task.detached` instead of `tokio::task::spawn_blocking`.
//

import CodexUtils
import Foundation

#if canImport(Darwin)
import Darwin
#endif

public let installationIdFilename = "installation_id"

public func resolveInstallationId(_ codexHome: AbsolutePathBuf) async throws -> String {
    let path = URL(fileURLWithPath: codexHome.join(installationIdFilename).path)
    try FileManager.default.createDirectory(
        atPath: codexHome.path,
        withIntermediateDirectories: true
    )
    return try await Task.detached(priority: .userInitiated) {
        try resolveInstallationIdBlocking(path)
    }.value
}

private func resolveInstallationIdBlocking(_ path: URL) throws -> String {
    if !FileManager.default.fileExists(atPath: path.path) {
        FileManager.default.createFile(atPath: path.path, contents: nil, attributes: [
            .posixPermissions: 0o644
        ])
    }
    let handle = try FileHandle(forUpdating: path)
    defer { try? handle.close() }

#if canImport(Darwin)
    var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
    let lockResult = fcntl(handle.fileDescriptor, F_SETLKW, &lock)
    guard lockResult != -1 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
    if let mode = attrs[.posixPermissions] as? NSNumber, (mode.uint16Value & 0o777) != 0o644 {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
    }
#endif

    let existing = String(data: handle.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !existing.isEmpty, let uuid = UUID(uuidString: existing) {
        return uuid.uuidString.lowercased()
    }

    let installationId = UUID().uuidString.lowercased()
    try handle.truncate(atOffset: 0)
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: Data(installationId.utf8))
    try handle.synchronize()
    return installationId
}
