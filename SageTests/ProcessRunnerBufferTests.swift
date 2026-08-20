@testable import Sage
import XCTest

final class ProcessRunnerBufferTests: XCTestCase {
    func testBufferStopsAtCap() {
        let buffer = LockedDataBuffer(maxBytes: 8)
        buffer.append(Data(repeating: 0x61, count: 5))
        buffer.append(Data(repeating: 0x62, count: 10))
        XCTAssertTrue(buffer.didTruncate)
        XCTAssertEqual(buffer.data.count, 8)
        XCTAssertEqual(buffer.data, Data("aaaaabbb".utf8))
    }

    func testBufferDoesNotTruncateUnderCap() {
        let buffer = LockedDataBuffer(maxBytes: 16)
        buffer.append(Data("hello".utf8))
        XCTAssertFalse(buffer.didTruncate)
        XCTAssertEqual(buffer.data, Data("hello".utf8))
    }
}
