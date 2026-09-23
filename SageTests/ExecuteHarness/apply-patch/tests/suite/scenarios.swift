@testable import ApplyPatch
@testable import Sage
import XCTest

/// Port of codex-rs/apply-patch/tests/suite/scenarios.rs.
/// Fixtures live at tests/fixtures/scenarios, matching the Codex tree.
final class ApplyPatchScenarioTests: XCTestCase {
    func testApplyPatchScenarios() throws {
        let scenarios = try FileManager.default.contentsOfDirectory(
            at: fixturesRoot(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter(\.hasDirectoryPath)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(scenarios.isEmpty, "expected transplanted Codex apply-patch fixtures")
        for scenario in scenarios {
            try runScenario(scenario)
        }
    }

    private func runScenario(_ dir: URL) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("apply-patch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let input = dir.appendingPathComponent("input")
        if FileManager.default.fileExists(atPath: input.path) {
            try copyDirectory(input, to: tmp)
        }

        let patch = try String(
            contentsOf: dir.appendingPathComponent("patch.txt"),
            encoding: .utf8
        )
        _ = try? applyPatch(
            patch,
            cwd: tmp,
            options: ApplyPatchOptions(updateFileMode: .preserveLineEndings, followSymlinks: true)
        )

        let expected = snapshot(dir.appendingPathComponent("expected"))
        let actual = snapshot(tmp)
        XCTAssertEqual(actual, expected, "Scenario \(dir.lastPathComponent) did not match expected final state")
    }

    private func fixturesRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/scenarios")
    }

    private func snapshot(_ root: URL) -> [String: Data] {
        var entries: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return entries
        }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            entries[relative] = (try? Data(contentsOf: url)) ?? Data()
        }
        return entries
    }

    private func copyDirectory(_ source: URL, to destination: URL) throws {
        let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            let relative = url.path.replacingOccurrences(of: source.path + "/", with: "")
            let dest = destination.appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: url, to: dest)
            }
        }
    }
}
