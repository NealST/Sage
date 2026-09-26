//
//  recovery.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/recovery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filesystem backup helpers are implemented. sqlx error-chain inspection is
//  mapped to `Error` / `NSError` codes. No GRDB schema is invented.
//

import Foundation

let BACKUP_DIR_NAME = "db-backups"

/// Path where the runtime database or sidecar lived before it was moved,
/// and the path where it was backed up.
public struct RuntimeDbBackup: Equatable, Sendable {
    public var originalPath: String
    public var backupPath: String

    public init(originalPath: String, backupPath: String) {
        self.originalPath = originalPath
        self.backupPath = backupPath
    }
}

public struct RuntimeDbInitError: Error, @unchecked Sendable {
    public var label: String
    public var operation: String
    public var path: String
    public var source: any Error

    public init(label: String, operation: String, path: String, source: any Error) {
        self.label = label
        self.operation = operation
        self.path = path
        self.source = source
    }
}

extension RuntimeDbInitError: LocalizedError {
    public var errorDescription: String? {
        "failed to \(operation) \(label) at \(path): \(source.localizedDescription)"
    }
}

/// Move one Codex runtime SQLite database out of the way so that database can
/// be recreated without discarding unrelated runtime databases.
public func backupRuntimeDbForFreshStart(dbPath: String) async throws -> [RuntimeDbBackup] {
    let sqliteHome = try parentDirectory(dbPath)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: sqliteHome, isDirectory: &isDirectory) {
        if isDirectory.boolValue {
            return try await backupRuntimeDbFiles(dbPath: dbPath)
        }
        return try await backupBlockingSqliteHome(sqliteHome)
    }
    try FileManager.default.createDirectory(
        atPath: sqliteHome,
        withIntermediateDirectories: true
    )
    throw recoveryIOError(
        "no Codex runtime database files were found to back up for \(dbPath)"
    )
}

public func runtimeDbPathForCorruptionError(_ error: any Error) -> String? {
    if !isSqliteCorruptionError(error) {
        return nil
    }
    return findRuntimeDbInitError(error)?.path
}

public func isSqliteCorruptionError(_ error: any Error) -> Bool {
    if let initError = error as? RuntimeDbInitError {
        return isSqliteCorruptionError(initError.source)
    }
    if sqliteErrorSourceIsCorruption(error) {
        return true
    }
    if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error {
        return isSqliteCorruptionError(underlying)
    }
    return false
}

func sqliteErrorSourceIsCorruption(_ source: any Error) -> Bool {
    let nsError = source as NSError
    if sqliteErrorDetailIsCorruption(nsError.localizedDescription)
        || sqliteErrorDetailIsCorruption(String(describing: source))
    {
        return true
    }
    return sqliteDatabaseCodeIsCorruption(String(nsError.code))
}

func sqliteDatabaseCodeIsCorruption(_ code: String) -> Bool {
    switch code.lowercased() {
    case "11", "26", "sqlite_corrupt", "sqlite_notadb":
        return true
    default:
        return false
    }
}

public func sqliteErrorDetailIsCorruption(_ detail: String) -> Bool {
    let detail = detail.lowercased()
    return detail.contains("database disk image is malformed")
        || detail.contains("database schema is malformed")
        || detail.contains("database is corrupt")
        || detail.contains("file is not a database")
        || detail.contains("sqlite_corrupt")
        || detail.contains("sqlite_notadb")
        || detail.contains("(code: 11)")
        || detail.contains("(code: 26)")
}

public func sqliteErrorDetailIsLock(_ detail: String) -> Bool {
    let detail = detail.lowercased()
    return detail.contains("database is locked") || detail.contains("database is busy")
}

func backupRuntimeDbFiles(dbPath: String) async throws -> [RuntimeDbBackup] {
    let sqliteHome = try parentDirectory(dbPath)
    return try await backupSqlitePaths(sqliteHome: sqliteHome, paths: sqlitePaths(dbPath))
}

func backupSqlitePaths(sqliteHome: String, paths: [String]) async throws -> [RuntimeDbBackup] {
    let backupParent = (sqliteHome as NSString).appendingPathComponent(BACKUP_DIR_NAME)
    let backupDir = try await createUniqueBackupDir(backupParent)
    var backups: [RuntimeDbBackup] = []

    for path in paths {
        if FileManager.default.fileExists(atPath: path) {
            let backupPath = (backupDir as NSString).appendingPathComponent(try fileName(path))
            try FileManager.default.moveItem(atPath: path, toPath: backupPath)
            backups.append(RuntimeDbBackup(originalPath: path, backupPath: backupPath))
        }
    }

    if backups.isEmpty {
        try? FileManager.default.removeItem(atPath: backupDir)
        throw recoveryIOError("no Codex runtime database files were found to back up")
    }

    return backups
}

func backupBlockingSqliteHome(_ sqliteHome: String) async throws -> [RuntimeDbBackup] {
    let parent = try parentDirectory(sqliteHome)
    let backupParent = (parent as NSString).appendingPathComponent(
        "\(try fileName(sqliteHome)).\(BACKUP_DIR_NAME)"
    )
    let backupDir = try await createUniqueBackupDir(backupParent)
    let backupPath = (backupDir as NSString).appendingPathComponent(try fileName(sqliteHome))
    try FileManager.default.moveItem(atPath: sqliteHome, toPath: backupPath)
    try FileManager.default.createDirectory(
        atPath: sqliteHome,
        withIntermediateDirectories: true
    )
    return [RuntimeDbBackup(originalPath: sqliteHome, backupPath: backupPath)]
}

func sqlitePaths(_ dbPath: String) -> [String] {
    [dbPath, dbPath + "-wal", dbPath + "-shm"]
}

func createUniqueBackupDir(_ backupParent: String) async throws -> String {
    try FileManager.default.createDirectory(
        atPath: backupParent,
        withIntermediateDirectories: true
    )
    let timestamp = UInt64(max(0, Date().timeIntervalSince1970))
    var sequence: UInt32 = 0
    while true {
        let backupDir = (backupParent as NSString)
            .appendingPathComponent("sqlite-\(timestamp)-\(sequence)")
        do {
            try FileManager.default.createDirectory(
                atPath: backupDir,
                withIntermediateDirectories: false
            )
            return backupDir
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteFileExistsError {
                sequence += 1
                continue
            }
            throw error
        }
    }
}

func fileName(_ path: String) throws -> String {
    let name = (path as NSString).lastPathComponent
    if name.isEmpty || name == "/" || path == name && (path == "." || path == "..") {
        throw recoveryIOError("cannot create a backup name for \(path)")
    }
    if path.hasSuffix("/") && name.isEmpty {
        throw recoveryIOError("cannot create a backup name for \(path)")
    }
    return name
}

func parentDirectory(_ path: String) throws -> String {
    let parent = (path as NSString).deletingLastPathComponent
    if parent.isEmpty || parent == path {
        throw recoveryIOError("database path does not have a parent directory: \(path)")
    }
    return parent
}

func findRuntimeDbInitError(_ error: any Error) -> RuntimeDbInitError? {
    if let initError = error as? RuntimeDbInitError {
        return initError
    }
    if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error {
        return findRuntimeDbInitError(underlying)
    }
    return nil
}

func recoveryIOError(_ message: String) -> Error {
    NSError(
        domain: NSPOSIXErrorDomain,
        code: Int(ENOENT),
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}
