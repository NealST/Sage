// Minimal XCTest implementation — real assertion semantics, no Xcode.
import Foundation

open class XCTestCase {
    public init() {}
    open func setUp() throws {}
    open func tearDown() throws {}
}

public var failures = 0
public var checks = 0

func fail(_ message: String, file: StaticString, line: UInt) {
    failures += 1
    FileHandle.standardError.write(Data("FAIL \(file):\(line): \(message)\n".utf8))
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    checks += 1
    if try !expression() { fail("XCTAssertTrue failed. \(message())", file: file, line: line) }
}
public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    checks += 1
    if try expression() { fail("XCTAssertFalse failed. \(message())", file: file, line: line) }
}
public func XCTAssertEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    checks += 1
    let (a, b) = (try expression1(), try expression2())
    if a != b { fail("XCTAssertEqual failed: \(a) != \(b). \(message())", file: file, line: line) }
}
public func XCTAssertNotEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    checks += 1
    if try expression1() == expression2() { fail("XCTAssertNotEqual failed. \(message())", file: file, line: line) }
}
public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    checks += 1
    if try expression() != nil { fail("XCTAssertNil failed. \(message())", file: file, line: line) }
}
public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    checks += 1
    if try expression() == nil { fail("XCTAssertNotNil failed. \(message())", file: file, line: line) }
}
public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    checks += 1
    fail("XCTFail. \(message)", file: file, line: line)
}
struct UnwrapError: Error {}
public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    checks += 1
    guard let value = try expression() else {
        fail("XCTUnwrap failed. \(message())", file: file, line: line)
        throw UnwrapError()
    }
    return value
}
public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    checks += 1
    do {
        _ = try expression()
    } catch {
        fail("XCTAssertNoThrow failed: threw \(error). \(message())", file: file, line: line)
    }
}
public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ errorHandler: (Error) -> Void = { _ in }) {
    checks += 1
    do {
        _ = try expression()
        fail("XCTAssertThrowsError failed: did not throw. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
