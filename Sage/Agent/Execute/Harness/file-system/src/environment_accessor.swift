//
//  environment_accessor.swift
//  FileSystem
//
//  Port of codex-rs/file-system/src/environment_accessor.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filesystem access bound to one environment configuration without exposing
//  its authority. Rust `Weak<dyn ExecutorFileSystem>` is `ObjectIdentifier`
//  of an `AnyObject` executor. Async methods replace boxed futures.
//

import CodexUtils
import Foundation

/// Filesystem operations authorized by the environment that supplied this borrowed accessor.
///
/// Callers cannot extract the underlying filesystem or choose another sandbox. They may retain
/// returned data, cache keys, and already-opened read streams after the accessor is gone.
public protocol EnvironmentAccess: Sendable {
    /// Identifies the filesystem and captured permissions without granting access to either.
    func cacheKey() -> EnvironmentAccessKey

    func canonicalize(_ path: PathUri) async throws -> PathUri

    func readFile(_ path: PathUri, options: ReadFileOptions) async throws -> [UInt8]

    /// Opens an owned stream; subsequent reads do not borrow or reauthorize through the accessor.
    func readFileStream(_ path: PathUri) async throws -> FileSystemReadStream

    func writeFile(_ path: PathUri, contents: [UInt8], options: WriteFileOptions) async throws

    func createDirectory(_ path: PathUri, options: CreateDirectoryOptions) async throws

    func getMetadata(_ path: PathUri, options: GetMetadataOptions) async throws -> FileMetadata

    func readDirectory(_ path: PathUri) async throws -> [ReadDirectoryEntry]

    func walk(_ path: PathUri, options: WalkOptions) async throws -> WalkOutcome

    func remove(_ path: PathUri, options: RemoveOptions) async throws

    func copy(
        sourcePath: PathUri,
        destinationPath: PathUri,
        options: CopyOptions
    ) async throws
}

extension EnvironmentAccess {
    public func readFileText(_ path: PathUri, options: ReadFileOptions) async throws -> String {
        let bytes = try await readFile(path, options: options)
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            throw IOError.invalidData("file is not valid UTF-8: \(path)")
        }
        return text
    }
}

/// Opaque identity for reusing data discovered with the same filesystem and permissions.
///
/// Holding this key keeps neither the underlying filesystem nor an accessor alive.
public struct EnvironmentAccessKey: Equatable, Sendable {
    let fileSystemID: ObjectIdentifier
    let sandbox: FileSystemSandboxContext?

    public static func == (lhs: EnvironmentAccessKey, rhs: EnvironmentAccessKey) -> Bool {
        lhs.fileSystemID == rhs.fileSystemID && lhs.sandbox == rhs.sandbox
    }
}

extension EnvironmentAccessKey: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fileSystemID)
        // Sandbox contexts compare by value but are not Hash. Collisions for different policies
        // on the same filesystem are harmless; equality still compares the complete context.
        hasher.combine(sandbox != nil)
    }
}

extension EnvironmentAccessKey: CustomDebugStringConvertible {
    public var debugDescription: String { "EnvironmentAccessKey(..)" }
}

/// Borrows a filesystem and forwards every operation with its captured sandbox configuration.
/// The underlying filesystem remains responsible for choosing sandboxed or direct access.
public struct FileSystemEnvironmentAccessor: EnvironmentAccess {
    let fileSystem: any ExecutorFileSystem
    let key: EnvironmentAccessKey

    /// Binds operations and cache identity to the captured environment permissions.
    public init(fileSystem: any ExecutorFileSystem, sandbox: FileSystemSandboxContext) {
        self.fileSystem = fileSystem
        self.key = EnvironmentAccessKey(
            fileSystemID: ObjectIdentifier(fileSystem),
            sandbox: sandbox
        )
    }

    /// Bypasses the filesystem sandbox. Use only for:
    ///
    /// 1. Tests.
    /// 2. Callers pending migration to sandboxed access.
    /// 3. Codex-internal operations that should never be sandboxed and that the model cannot trigger.
    ///
    /// Model-turn discovery must use the accessor supplied by its selected environment.
    public static func unrestricted(fileSystem: any ExecutorFileSystem) -> FileSystemEnvironmentAccessor {
        FileSystemEnvironmentAccessor(fileSystem: fileSystem, sandbox: nil)
    }

    private init(fileSystem: any ExecutorFileSystem, sandbox: FileSystemSandboxContext?) {
        self.fileSystem = fileSystem
        self.key = EnvironmentAccessKey(
            fileSystemID: ObjectIdentifier(fileSystem),
            sandbox: sandbox
        )
    }

    public func cacheKey() -> EnvironmentAccessKey {
        key
    }

    public func canonicalize(_ path: PathUri) async throws -> PathUri {
        try await fileSystem.canonicalize(path, sandbox: key.sandbox)
    }

    public func readFile(_ path: PathUri, options: ReadFileOptions) async throws -> [UInt8] {
        try await fileSystem.readFile(path, options: options, sandbox: key.sandbox)
    }

    public func readFileStream(_ path: PathUri) async throws -> FileSystemReadStream {
        try await fileSystem.readFileStream(path, sandbox: key.sandbox)
    }

    public func writeFile(
        _ path: PathUri,
        contents: [UInt8],
        options: WriteFileOptions
    ) async throws {
        try await fileSystem.writeFile(path, contents: contents, options: options, sandbox: key.sandbox)
    }

    public func createDirectory(_ path: PathUri, options: CreateDirectoryOptions) async throws {
        try await fileSystem.createDirectory(path, options: options, sandbox: key.sandbox)
    }

    public func getMetadata(_ path: PathUri, options: GetMetadataOptions) async throws -> FileMetadata {
        try await fileSystem.getMetadata(path, options: options, sandbox: key.sandbox)
    }

    public func readDirectory(_ path: PathUri) async throws -> [ReadDirectoryEntry] {
        try await fileSystem.readDirectory(path, sandbox: key.sandbox)
    }

    public func walk(_ path: PathUri, options: WalkOptions) async throws -> WalkOutcome {
        try await fileSystem.walk(path, options: options, sandbox: key.sandbox)
    }

    public func remove(_ path: PathUri, options: RemoveOptions) async throws {
        try await fileSystem.remove(path, options: options, sandbox: key.sandbox)
    }

    public func copy(
        sourcePath: PathUri,
        destinationPath: PathUri,
        options: CopyOptions
    ) async throws {
        try await fileSystem.copy(
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            options: options,
            sandbox: key.sandbox
        )
    }
}
