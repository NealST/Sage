//
//  SafeFileIO+Directory.swift
//  Sage
//
//  Descriptor-anchored directory create and copy.
//

import Darwin
import Foundation

extension SafeFileIO {
    static func createDirectory(at url: URL) throws {
        let descriptor = try createDirectoryTree(to: url)
        Darwin.close(descriptor)
    }

    /// Opens `url`, creating any missing parents with `mkdirat` from an already-verified ancestor.
    static func createDirectoryTree(to url: URL) throws -> Int32 {
        let resolved = try PathGuard.resolveAllowed(url.path, access: .write)
        try PathGuard.assertWriteAllowed(resolved)
        if let existing = try openExistingDirectory(resolved, access: .write) {
            return existing
        }
        let name = resolved.lastPathComponent
        try validateFileName(name)
        let parent = resolved.deletingLastPathComponent()
        guard parent.path != resolved.path else {
            throw posixError(operation: "create directory", path: resolved.path)
        }
        let parentDescriptor = try createDirectoryTree(to: parent)
        defer { Darwin.close(parentDescriptor) }
        return try makeDirectoryChild(
            named: name,
            in: parentDescriptor,
            path: resolved.path,
        )
    }

    static func copyDirectory(at source: URL, to destination: URL) throws {
        try PathGuard.assertSensitiveReadAllowed(source)
        try FileTransferDestination.assertNotRelocatingProtectedRoot(source)
        let sourceDescriptor = try openDirectory(source, access: .read)
        defer { Darwin.close(sourceDescriptor) }
        let destinationDescriptor = try createDirectoryTree(to: destination)
        defer { Darwin.close(destinationDescriptor) }
        try copyOpenedDirectory(from: sourceDescriptor, to: destinationDescriptor)
    }
}

extension SafeFileIO {
    private static func openExistingDirectory(
        _ url: URL,
        access: PathGuard.Access,
    ) throws -> Int32? {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
        )
        if descriptor >= 0 {
            do {
                try verifyDescriptor(descriptor, access: access)
                return descriptor
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }
        guard errno == ENOENT else {
            throw posixError(operation: "open directory", path: url.path)
        }
        return nil
    }

    private static func makeDirectoryChild(
        named name: String,
        in parentDescriptor: Int32,
        path: String,
    ) throws -> Int32 {
        let created = Darwin.mkdirat(
            parentDescriptor,
            name,
            S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH,
        )
        guard created == 0 || errno == EEXIST else {
            throw posixError(operation: "create directory", path: path)
        }
        let child = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
        )
        guard child >= 0 else {
            throw posixError(operation: "open directory", path: path)
        }
        do {
            try verifyDescriptor(child, access: .write)
            return child
        } catch {
            Darwin.close(child)
            throw error
        }
    }

    private static func copyOpenedDirectory(from source: Int32, to destination: Int32) throws {
        let listing = Darwin.dup(source)
        guard listing >= 0 else {
            throw posixError(operation: "list directory", path: "(descriptor)")
        }
        guard let stream = fdopendir(listing) else {
            Darwin.close(listing)
            throw posixError(operation: "list directory", path: "(descriptor)")
        }
        defer { closedir(stream) }
        try copyDirectoryEntries(from: stream, source: source, to: destination)
    }

    private static func copyDirectoryEntries(
        from stream: UnsafeMutablePointer<DIR>,
        source: Int32,
        to destination: Int32,
    ) throws {
        while let entry = readdir(stream) {
            try Task.checkCancellation()
            guard let name = directoryEntryName(entry), name != ".", name != ".." else { continue }
            try copyDirectoryEntry(named: name, from: source, to: destination)
        }
    }

    private static func directoryEntryName(_ entry: UnsafeMutablePointer<dirent>) -> String? {
        withUnsafeBytes(of: entry.pointee.d_name) { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return nil
            }
            let name = String(cString: base)
            return name.isEmpty ? nil : name
        }
    }
}

extension SafeFileIO {
    private static func copyDirectoryEntry(
        named name: String,
        from source: Int32,
        to destination: Int32,
    ) throws {
        try validateFileName(name)
        var info = Darwin.stat()
        guard fstatat(source, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return }
        let type = info.st_mode & S_IFMT
        if type == S_IFDIR {
            try copyDirectoryChild(named: name, from: source, to: destination)
        } else if type == S_IFREG {
            try copyRegularChild(named: name, from: source, to: destination)
        }
    }

    private static func copyDirectoryChild(
        named name: String,
        from source: Int32,
        to destination: Int32,
    ) throws {
        let childSource = try openatDirectory(named: name, in: source, access: .read)
        defer { Darwin.close(childSource) }
        let childURL = try descriptorURL(childSource, access: .read)
        if SensitiveResourcePolicy.wouldRelocateProtectedRoot(source: childURL) {
            return
        }
        let childDestination = try makeDirectoryChild(
            named: name,
            in: destination,
            path: childURL.path,
        )
        defer { Darwin.close(childDestination) }
        try copyOpenedDirectory(from: childSource, to: childDestination)
    }

    private static func copyRegularChild(
        named name: String,
        from source: Int32,
        to destination: Int32,
    ) throws {
        let childSource = Darwin.openat(
            source,
            name,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC,
        )
        guard childSource >= 0 else { return }
        defer { Darwin.close(childSource) }
        try verifyDescriptor(childSource, access: .read)
        let childDestination = Darwin.openat(
            destination,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR,
        )
        guard childDestination >= 0 else {
            throw posixError(operation: "create destination", path: name)
        }
        var shouldRemove = true
        defer {
            Darwin.close(childDestination)
            if shouldRemove {
                _ = Darwin.unlinkat(destination, name, 0)
            }
        }
        try finishCopy(from: childSource, to: childDestination, name: name)
        shouldRemove = false
    }

    private static func finishCopy(from source: Int32, to destination: Int32, name: String) throws {
        guard fcopyfile(source, destination, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
            throw posixError(operation: "copy", path: name)
        }
        guard Darwin.fsync(destination) == 0 else {
            throw posixError(operation: "flush", path: name)
        }
    }

    private static func openatDirectory(
        named name: String,
        in parent: Int32,
        access: PathGuard.Access,
    ) throws -> Int32 {
        let child = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
        )
        guard child >= 0 else {
            throw posixError(operation: "open directory", path: name)
        }
        do {
            try verifyDescriptor(child, access: access)
            return child
        } catch {
            Darwin.close(child)
            throw error
        }
    }

    private static func descriptorURL(
        _ descriptor: Int32,
        access: PathGuard.Access,
    ) throws -> URL {
        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = pathBuffer.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return Int32(-1) }
            return Darwin.fcntl(descriptor, F_GETPATH, UnsafeMutableRawPointer(baseAddress))
        }
        guard result == 0 else {
            throw posixError(operation: "verify opened path", path: "(descriptor)")
        }
        return try PathGuard.resolveAllowed(String(cString: pathBuffer), access: access)
    }
}
