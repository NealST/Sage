//
//  SafeFileIO.swift
//  Sage
//
//  Descriptor-anchored file access used after PathGuard validation.
//

import Darwin
import Foundation

nonisolated enum SafeFileIO {
    static func openForReading(at url: URL) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw posixError(operation: "open", path: url.path)
        }
        do {
            try verifyDescriptor(descriptor, access: .read)
            return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func readData(at url: URL, maxBytes: Int) throws -> Data {
        let handle = try openForReading(at: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else {
            throw ToolError.operationFailed(
                "File too large (over \(maxBytes) bytes). Use line_start/line_end to read a section."
            )
        }
        return data
    }

    static func atomicWrite(_ data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try PathGuard.assertWriteAllowed(parent)
        let directoryDescriptor = try createDirectoryTree(to: parent)
        defer { Darwin.close(directoryDescriptor) }

        let fileName = url.lastPathComponent
        try validateFileName(fileName)
        let temporaryName = ".sage-write-\(UUID().uuidString)"
        let fileDescriptor = Darwin.openat(
            directoryDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard fileDescriptor >= 0 else {
            throw posixError(operation: "create temporary file", path: parent.path)
        }

        var shouldRemoveTemporaryFile = true
        defer {
            Darwin.close(fileDescriptor)
            if shouldRemoveTemporaryFile {
                _ = Darwin.unlinkat(directoryDescriptor, temporaryName, 0)
            }
        }
        try writeAll(data, descriptor: fileDescriptor, path: url.path)
        guard Darwin.fsync(fileDescriptor) == 0 else {
            throw posixError(operation: "flush", path: url.path)
        }
        guard Darwin.renameat(directoryDescriptor, temporaryName, directoryDescriptor, fileName) == 0 else {
            throw posixError(operation: "replace", path: url.path)
        }
        shouldRemoveTemporaryFile = false
    }

    static func removeItem(at url: URL, isDirectory: Bool) throws {
        let parentDescriptor = try openDirectory(url.deletingLastPathComponent(), access: .write)
        defer { Darwin.close(parentDescriptor) }
        let fileName = url.lastPathComponent
        try validateFileName(fileName)

        if isDirectory {
            let directoryDescriptor = Darwin.openat(
                parentDescriptor,
                fileName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard directoryDescriptor >= 0 else {
                throw posixError(operation: "open directory", path: url.path)
            }
            _ = Darwin.unlinkat(directoryDescriptor, ".DS_Store", 0)
            Darwin.close(directoryDescriptor)
        }

        let flags = isDirectory ? AT_REMOVEDIR : 0
        guard Darwin.unlinkat(parentDescriptor, fileName, flags) == 0 else {
            throw posixError(operation: "delete", path: url.path)
        }
    }

    static func moveItem(at source: URL, to destination: URL) throws {
        let sourceDirectory = try openDirectory(source.deletingLastPathComponent(), access: .write)
        defer { Darwin.close(sourceDirectory) }
        let destinationDirectory = try openDirectory(destination.deletingLastPathComponent(), access: .write)
        defer { Darwin.close(destinationDirectory) }
        let sourceName = source.lastPathComponent
        let destinationName = destination.lastPathComponent
        try validateFileName(sourceName)
        try validateFileName(destinationName)

        guard Darwin.renameat(
            sourceDirectory,
            sourceName,
            destinationDirectory,
            destinationName
        ) == 0 else {
            throw posixError(operation: "move", path: source.path)
        }
    }

    static func copyRegularFile(at source: URL, to destination: URL) throws {
        let sourceHandle = try openForReading(at: source)
        defer { try? sourceHandle.close() }
        try PathGuard.assertWriteAllowed(destination.deletingLastPathComponent())
        let destinationDirectory = try createDirectoryTree(
            to: destination.deletingLastPathComponent(),
        )
        defer { Darwin.close(destinationDirectory) }
        let destinationName = destination.lastPathComponent
        try validateFileName(destinationName)
        let destinationDescriptor = Darwin.openat(
            destinationDirectory,
            destinationName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard destinationDescriptor >= 0 else {
            throw posixError(operation: "create destination", path: destination.path)
        }
        var shouldRemoveDestination = true
        defer {
            Darwin.close(destinationDescriptor)
            if shouldRemoveDestination {
                _ = Darwin.unlinkat(destinationDirectory, destinationName, 0)
            }
        }

        guard fcopyfile(
            sourceHandle.fileDescriptor,
            destinationDescriptor,
            nil,
            copyfile_flags_t(COPYFILE_ALL)
        ) == 0 else {
            throw posixError(operation: "copy", path: source.path)
        }
        guard Darwin.fsync(destinationDescriptor) == 0 else {
            throw posixError(operation: "flush", path: destination.path)
        }
        shouldRemoveDestination = false
    }

    static func verifyDescriptor(_ descriptor: Int32, access: PathGuard.Access) throws {
        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = pathBuffer.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return Int32(-1) }
            return Darwin.fcntl(descriptor, F_GETPATH, UnsafeMutableRawPointer(baseAddress))
        }
        guard result == 0 else {
            throw posixError(operation: "verify opened path", path: "(descriptor)")
        }
        let openedPath = String(cString: pathBuffer)
        let openedURL = try PathGuard.resolveAllowed(openedPath, access: access)
        switch access {
        case .read:
            try PathGuard.assertSensitiveReadAllowed(openedURL)

        case .write:
            try PathGuard.assertWriteAllowed(openedURL)
        }
    }

    static func openDirectory(_ url: URL, access: PathGuard.Access) throws -> Int32 {
        let resolved = try PathGuard.resolveAllowed(url.path, access: access)
        let descriptor = Darwin.open(
            resolved.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw posixError(operation: "open directory", path: resolved.path)
        }
        do {
            try verifyDescriptor(descriptor, access: access)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func validateFileName(_ fileName: String) throws {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/") else {
            throw ToolError.invalidArguments("Invalid file name.")
        }
    }

    private static func writeAll(_ data: Data, descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    bytes.count - written
                )
                guard count > 0 else {
                    throw posixError(operation: "write", path: path)
                }
                written += count
            }
        }
    }

    static func posixError(operation: String, path: String) -> ToolError {
        let message = String(cString: strerror(errno))
        return .operationFailed("Could not \(operation) \(path): \(message)")
    }
}
