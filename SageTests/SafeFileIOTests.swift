@testable import Sage
import XCTest

final class SafeFileIOTests: XCTestCase {
    private var fixtureRoot: URL?

    override func setUpWithError() throws {
        fixtureRoot = nil
    }

    override func tearDownWithError() throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testRejectsFinalSymlinkAndWritesThroughAnchoredDirectory() throws {
        let root = try makeFixture()
        let actual = root.appendingPathComponent("actual.txt")
        let link = root.appendingPathComponent("link.txt")
        try "original".write(to: actual, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)

        try PathGuard.$policy.withValue(.home) {
            try PathGuard.$writeAllowlist.withValue([root.path]) {
                XCTAssertThrowsError(try SafeFileIO.openForReading(at: link))
                let destination = root.appendingPathComponent("written.txt")
                try SafeFileIO.atomicWrite(Data("updated".utf8), to: destination)
                XCTAssertEqual(
                    try String(data: SafeFileIO.readData(at: destination, maxBytes: 100), encoding: .utf8),
                    "updated"
                )
            }
        }
    }

    func testCopiesDirectoryEntriesWithPerChildValidation() throws {
        let root = try makeFixture()
        let source = root.appendingPathComponent("source-dir", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "one".write(to: source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: nested.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let destination = root.appendingPathComponent("dest-dir", isDirectory: true)

        try PathGuard.$policy.withValue(.home) {
            try PathGuard.$writeAllowlist.withValue([root.path]) {
                try SafeFileIO.copyDirectory(at: source, to: destination)
                XCTAssertEqual(try readText(destination.appendingPathComponent("a.txt")), "one")
                XCTAssertEqual(try readText(destination.appendingPathComponent("nested/b.txt")), "two")
            }
        }
    }

    func testCreateDirectoryCreatesNestedParentsAndIsIdempotent() throws {
        let root = try makeFixture()
        let nested = root.appendingPathComponent("a/b/c", isDirectory: true)

        try PathGuard.$policy.withValue(.home) {
            try PathGuard.$writeAllowlist.withValue([root.path]) {
                try SafeFileIO.createDirectory(at: nested)
                try SafeFileIO.createDirectory(at: nested)
                var isDirectory: ObjCBool = false
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory),
                )
                XCTAssertTrue(isDirectory.boolValue)
            }
        }
    }

    func testCreateDirectoryRejectsFileAsParent() throws {
        let root = try makeFixture()
        let file = root.appendingPathComponent("not-a-dir")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let nested = file.appendingPathComponent("child", isDirectory: true)

        try PathGuard.$policy.withValue(.home) {
            try PathGuard.$writeAllowlist.withValue([root.path]) {
                XCTAssertThrowsError(try SafeFileIO.createDirectory(at: nested))
            }
        }
    }

    func testCopyDirectorySkipsSymlinkChildren() throws {
        let root = try makeFixture()
        let source = root.appendingPathComponent("source-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "keep".write(to: source.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("link.txt"),
            withDestinationURL: source.appendingPathComponent("keep.txt"),
        )
        let destination = root.appendingPathComponent("dest-dir", isDirectory: true)

        try PathGuard.$policy.withValue(.home) {
            try PathGuard.$writeAllowlist.withValue([root.path]) {
                try SafeFileIO.copyDirectory(at: source, to: destination)
                XCTAssertEqual(try readText(destination.appendingPathComponent("keep.txt")), "keep")
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: destination.appendingPathComponent("link.txt").path,
                    ),
                )
            }
        }
    }

    func testMoveCopyAndDeleteStayDescriptorAnchored() throws {
        let root = try makeFixture()
        let source = root.appendingPathComponent("source.txt")
        let copied = root.appendingPathComponent("copied.txt")
        let moved = root.appendingPathComponent("moved.txt")
        try "content".write(to: source, atomically: true, encoding: .utf8)

        try PathGuard.$policy.withValue(.home) {
            try PathGuard.$writeAllowlist.withValue([root.path]) {
                try SafeFileIO.copyRegularFile(at: source, to: copied)
                try SafeFileIO.moveItem(at: copied, to: moved)
                XCTAssertEqual(try readText(moved), "content")
                try SafeFileIO.removeItem(at: moved, isDirectory: false)
                XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
            }
        }
    }

    private func readText(_ url: URL) throws -> String? {
        try String(data: SafeFileIO.readData(at: url, maxBytes: 100), encoding: .utf8)
    }

    private func makeFixture() throws -> URL {
        if let fixtureRoot {
            return fixtureRoot
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Caches/SageSafeFileIO-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fixtureRoot = root
        return root
    }
}
