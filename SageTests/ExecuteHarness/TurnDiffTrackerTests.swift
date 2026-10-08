@testable import Sage
@testable import CodexCore
import ApplyPatch
import XCTest

final class ExecuteHarnessTurnDiffTrackerTests: XCTestCase {
    func testAddThenUpdateAccumulatesAsASingleAdd() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTurnDiff-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("a.txt")
        let tracker = TurnDiffTracker.withEnvironmentDisplayRoots([("", root.path)])
        tracker.trackDelta(
            "",
            AppliedPatchDelta(changes: [
                AppliedPatchChange(path: file, kind: .add(content: "foo\n", overwrittenContent: nil)),
            ])
        )
        tracker.trackDelta(
            "",
            AppliedPatchDelta(changes: [
                AppliedPatchChange(
                    path: file,
                    kind: .update(
                        movePath: nil,
                        oldContent: "foo\n",
                        overwrittenMoveContent: nil,
                        newContent: "foo\nbar\n"
                    )
                ),
            ])
        )
        let rightOID = gitBlobOID("foo\nbar\n")
        let expected = """
        diff --git a/a.txt b/a.txt
        new file mode 100644
        index \(String(repeating: "0", count: 40))..\(rightOID)
        --- /dev/null
        +++ b/a.txt
        @@ -0,0 +1,2 @@
        +foo
        +bar

        """
        XCTAssertEqual(tracker.getUnifiedDiff(), expected)
    }

    func testInvalidateClearsAnExistingDiff() {
        let file = URL(fileURLWithPath: "/tmp/a.txt")
        let tracker = TurnDiffTracker()
        tracker.trackDelta(
            "",
            AppliedPatchDelta(changes: [
                AppliedPatchChange(path: file, kind: .add(content: "foo\n", overwrittenContent: nil)),
            ])
        )
        XCTAssertTrue(tracker.hasUnifiedDiff())
        tracker.invalidate()
        XCTAssertNil(tracker.getUnifiedDiff())
        tracker.trackDelta(
            "",
            AppliedPatchDelta(changes: [
                AppliedPatchChange(path: file, kind: .add(content: "bar\n", overwrittenContent: nil)),
            ])
        )
        XCTAssertNil(tracker.getUnifiedDiff())
    }

    func testInexactDeltaInvalidates() {
        let file = URL(fileURLWithPath: "/tmp/a.txt")
        let tracker = TurnDiffTracker()
        tracker.trackDelta(
            "",
            AppliedPatchDelta(changes: [
                AppliedPatchChange(path: file, kind: .add(content: "foo\n", overwrittenContent: nil)),
            ])
        )
        tracker.trackDelta("", AppliedPatchDelta(changes: [], exact: false))
        XCTAssertNil(tracker.getUnifiedDiff())
    }
}
