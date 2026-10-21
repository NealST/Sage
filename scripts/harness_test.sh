#!/bin/zsh
# harness_test.sh — build ExecuteHarness modules and run their tests without
# xcodebuild (the Xcode license prompt blocks `swift build` on this machine).
#
# Uses the Xcode toolchain binaries directly and a minimal XCTest
# implementation (scripts/xctest_shim.swift). Once `sudo xcodebuild -license
# accept` has been run, prefer the real path: xcodebuild test / swift test.
#
# The generated runner has an async main: tests are awaited in order. Do NOT
# bridge sync→async with Task + DispatchSemaphore — blocking the main thread
# deadlocks any Task that inherits main-actor isolation.
#
# Usage: scripts/harness_test.sh
set -euo pipefail

SAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$SAGE_ROOT/Sage/Agent/Execute/Harness"
TESTS="$SAGE_ROOT/SageTests/ExecuteHarness"
TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
TARGET=arm64-apple-macosx15.0
BUILD=/tmp/harness_test_build
RUNNER=/tmp/harness_test_runner

rm -rf "$BUILD" "$RUNNER"
mkdir -p "$BUILD" "$RUNNER"

# --- modules (name:sources, built in dependency order) ----------------------
# Optional -l<lib> flags before the source list link module dependencies.
build_module() {
  local name="$1"; shift
  local deps=()
  while [[ "$1" == -l* ]]; do deps+=("$1"); shift; done
  echo "== build $name"
  "$TC" -emit-module -emit-library -enable-testing \
    -module-name "$name" -sdk "$SDK" -target "$TARGET" \
    -emit-module-path "$BUILD/$name.swiftmodule" -o "$BUILD/lib$name.dylib" \
    -I "$BUILD" -L "$BUILD" "${deps[@]}" "$@"
}

# Minimal XCTest implementation (real assertion semantics).
"$TC" -emit-module -emit-library -module-name XCTest -sdk "$SDK" -target "$TARGET" \
  -emit-module-path "$BUILD/XCTest.swiftmodule" -o "$BUILD/libXCTest.dylib" \
  "$SAGE_ROOT/scripts/xctest_shim.swift"

# Source trees match the package targets (§4.1): SageUtils is the whole
# utils/ tree, SageProtocol the whole protocol/src tree — recurse via find.
build_module SageAsyncUtils "$HARNESS"/async-utils/src/*.swift
build_module SageUtils $(find "$HARNESS/utils" -name '*.swift' | sort)
build_module SageProtocol -lSageUtils $(find "$HARNESS/protocol/src" -name '*.swift' | sort)

# --- generated runner --------------------------------------------------------
python3 - "$TESTS" "$RUNNER/runner.swift" <<'EOF'
import re, glob, sys, os

tests_dir, out_path = sys.argv[1], sys.argv[2]
# Only suites whose modules this script builds (app-target suites like
# apply-patch import Sage and run through xcodebuild instead).
files = sorted(
    glob.glob(os.path.join(tests_dir, "protocol/tests/suite/*.swift"))
    + glob.glob(os.path.join(tests_dir, "utils/**/tests/suite/*.swift"), recursive=True)
    + glob.glob(os.path.join(tests_dir, "async-utils/tests/suite/*.swift"))
)
out = ["import Foundation", "@testable import SageProtocol", "@testable import SageUtils",
       "@testable import SageAsyncUtils",
       "import XCTest", "",
       "func report(_ s: String) { FileHandle.standardError.write(Data((s + \"\\n\").utf8)) }", "",
       "@main struct TestRunner { static func main() async throws {"]
count = 0
for f in files:
    src = open(f).read()
    m = re.search(r"final class (\w+): XCTestCase", src)
    if not m:
        continue
    cls = m.group(1)
    for method, is_async, throws in re.findall(r"func (test\w+)\(\)\s*(async\s+)?(throws)?\s*\{", src):
        if is_async:
            call = f"try await t.{method}()" if throws else f"await t.{method}()"
        else:
            call = f"try t.{method}()" if throws else f"t.{method}()"
        out.append(f'    do {{ let t = {cls}(); t.setUp(); {call}; t.tearDown(); report("PASS {cls}.{method}") }} '
                   f'catch {{ report("FAIL {cls}.{method}: \\(error)"); failures += 1 }}')
        count += 1
out.append('    report("\\(checks) checks, \\(failures) failures")')
out.append('    if failures > 0 { fatalError("test failures") }')
out.append("} }")
open(out_path, "w").write("\n".join(out))
print(f"== runner: {count} tests from {len(files)} files")
EOF

# --- compile & run -----------------------------------------------------------
echo "== link runner"
(cd "$TESTS" && "$TC" -o "$RUNNER/runner" -sdk "$SDK" -target "$TARGET" \
  -I "$BUILD" -L "$BUILD" -lSageProtocol -lSageUtils -lSageAsyncUtils -lXCTest \
  protocol/tests/suite/*.swift utils/*/tests/suite/*.swift async-utils/tests/suite/*.swift \
  "$RUNNER/runner.swift")

echo "== run"
DYLD_LIBRARY_PATH="$BUILD" "$RUNNER/runner"
