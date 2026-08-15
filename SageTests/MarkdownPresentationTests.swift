import XCTest
@testable import Sage

final class MarkdownPresentationTests: XCTestCase {
    func testSoftensCheckedTasks() {
        let input = """
        - [ ] open
        - [x] done
        * [X] also done
        1. [x] numbered
        """
        let out = MarkdownPresentation.softenCompletedTasks(in: input)
        XCTAssertTrue(out.contains("- [ ] open"))
        XCTAssertTrue(out.contains("- [x] ~~done~~"))
        XCTAssertTrue(out.contains("* [X] ~~also done~~"))
        XCTAssertTrue(out.contains("1. [x] ~~numbered~~"))
    }

    func testSkipsAlreadyStruckAndCodeFences() {
        let input = """
        - [x] ~~already~~
        ```
        - [x] not a task
        ```
        - [x] after
        """
        let out = MarkdownPresentation.softenCompletedTasks(in: input)
        XCTAssertTrue(out.contains("- [x] ~~already~~"))
        XCTAssertFalse(out.contains("~~not a task~~"))
        XCTAssertTrue(out.contains("- [x] ~~after~~"))
    }

    func testLeavesPlainMarkdownUntouchedFastPath() {
        let input = "Hello\n\n- item\n"
        XCTAssertEqual(MarkdownPresentation.softenCompletedTasks(in: input), input)
    }
}
