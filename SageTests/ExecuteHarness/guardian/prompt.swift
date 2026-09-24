@testable import Sage
import XCTest

final class ExecuteHarnessGuardianPromptTests: XCTestCase {
    func testParseAllowDenyAndAsk() {
        XCTAssertEqual(GuardianPrompt.parse("ALLOW"), .approved)
        XCTAssertEqual(
            GuardianPrompt.parse("DENY wipe the disk"),
            .denied(reason: "wipe the disk")
        )
        XCTAssertNil(GuardianPrompt.parse("ASK let the user decide"))
        XCTAssertNil(GuardianPrompt.parse("not a decision"))
    }
}
