//
//  find_up.swift
//  SageTests
//
//  Port of codex-rs/file-system find-up behavior (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Finds the nearest ancestor that contains a marker file in a temp dir.
//

import CodexUtils
import FileSystem
import Foundation
import XCTest

final class FindUpTests: XCTestCase {
    private var tempRoot: String?

    override func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(atPath: tempRoot)
        }
        super.tearDown()
    }

    func testFindsNearestAncestorWithMarkerFile() async throws {
        let root = NSTemporaryDirectory() + "find-up-" + UUID().uuidString
        tempRoot = root
        let nested = (root as NSString).appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        let markerDir = (root as NSString).appendingPathComponent("a")
        try "marker".write(
            toFile: (markerDir as NSString).appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let fs = LocalTestFileSystem()
        let start = try PathUri.fromHostNativePath(nested)
        let found = try await findNearestAncestorWithMarkers(
            fileSystem: fs,
            start: start,
            markers: ["AGENTS.md"],
            errorPolicy: .propagate,
            sandbox: nil
        )
        XCTAssertEqual(found, try PathUri.fromHostNativePath(markerDir))
    }

    func testNativeSearchFindsSameAncestor() async throws {
        let root = NSTemporaryDirectory() + "find-up-native-" + UUID().uuidString
        tempRoot = root
        let nested = (root as NSString).appendingPathComponent("pkg/src")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        try "ok".write(
            toFile: (root as NSString).appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        let fs = LocalTestFileSystem()
        let start = try AbsolutePathBuf.fromAbsolutePath(nested)
        let found = try await findNearestNativeAncestorWithMarkers(
            fileSystem: fs,
            start: start,
            markers: [".git"],
            errorPolicy: .ignore,
            sandbox: nil
        )
        XCTAssertEqual(found, try AbsolutePathBuf.fromAbsolutePath(root))
    }
}

/// Minimal local `ExecutorFileSystem` for marker-search tests.
private final class LocalTestFileSystem: ExecutorFileSystem, @unchecked Sendable {
    func canonicalize(_ path: PathUri, sandbox: FileSystemSandboxContext?) async throws -> PathUri {
        PathUri.fromAbsPath(try path.toAbsPath().canonicalize())
    }

    func readFile(
        _ path: PathUri,
        options: ReadFileOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> [UInt8] {
        Array(try Data(contentsOf: URL(fileURLWithPath: try path.toAbsPath().asPath)))
    }

    func readFileStream(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> FileSystemReadStream {
        let data = try await readFile(path, options: .default, sandbox: sandbox)
        return FileSystemReadStream(AsyncThrowingStream { continuation in
            continuation.yield(Data(data))
            continuation.finish()
        })
    }

    func writeFile(
        _ path: PathUri,
        contents: [UInt8],
        options: WriteFileOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {
        try Data(contents).write(to: URL(fileURLWithPath: try path.toAbsPath().asPath))
    }

    func createDirectory(
        _ path: PathUri,
        options: CreateDirectoryOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {
        try FileManager.default.createDirectory(
            atPath: try path.toAbsPath().asPath,
            withIntermediateDirectories: options.recursive
        )
    }

    func getMetadata(
        _ path: PathUri,
        options: GetMetadataOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> FileMetadata {
        let native = try path.toAbsPath().asPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: native, isDirectory: &isDir) else {
            throw IOError.notFound(native)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: native)
        let isSymlink = (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let created = Int64(((attrs[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000)
        let modified = Int64(((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000)
        return FileMetadata(
            isDirectory: isDir.boolValue,
            isFile: !isDir.boolValue,
            isSymlink: isSymlink,
            size: size,
            createdAtMs: created,
            modifiedAtMs: modified
        )
    }

    func readDirectory(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> [ReadDirectoryEntry] {
        []
    }

    func walk(
        _ path: PathUri,
        options: WalkOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> WalkOutcome {
        WalkOutcome()
    }

    func remove(
        _ path: PathUri,
        options: RemoveOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {}

    func copy(
        sourcePath: PathUri,
        destinationPath: PathUri,
        options: CopyOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {}
}
