#!/bin/zsh
# harness_test.sh — build ExecuteHarness modules and run their tests without
# xcodebuild (the Xcode license prompt blocks `swift build` on this machine).
#
# Uses the Xcode toolchain binaries directly and a minimal XCTest
# implementation (scripts/xctest_shim.swift). Once `sudo xcodebuild -license
# accept` has been run, prefer the real path: xcodebuild test / swift test.
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

# --- modules (name:source-dir, built in dependency order) -------------------
build_module() {
  local name="$1"; shift
  echo "== build $name"
  "$TC" -emit-module -emit-library -enable-testing \
    -module-name "$name" -sdk "$SDK" -target "$TARGET" \
    -emit-module-path "$BUILD/$name.swiftmodule" -o "$BUILD/lib$name.dylib" \
    -I "$BUILD" "$@"
}

# Minimal XCTest implementation (real assertion semantics).
"$TC" -emit-module -emit-library -module-name XCTest -sdk "$SDK" -target "$TARGET" \
  -emit-module-path "$BUILD/XCTest.swiftmodule" -o "$BUILD/libXCTest.dylib" \
  "$SAGE_ROOT/scripts/xctest_shim.swift"

build_module CodexAsyncUtils "$HARNESS"/async-utils/src/*.swift
build_module CodexUtils "$HARNESS"/utils/io_error.swift "$HARNESS"/utils/absolute-path/src/*.swift \
  "$HARNESS"/utils/path-uri/src/*.swift "$HARNESS"/utils/cache/src/*.swift \
  "$HARNESS"/utils/home-dir/src/*.swift "$HARNESS"/utils/path-utils/src/*.swift \
  "$HARNESS"/utils/string/src/*.swift "$HARNESS"/utils/stream-parser/src/*.swift
build_module CodexProtocol "$HARNESS"/protocol/src/*.swift "$HARNESS"/protocol/src/models/*.swift

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
out = ["import Foundation", "@testable import CodexProtocol", "@testable import CodexUtils",
       "@testable import CodexAsyncUtils",
       "import XCTest", "",
       "func report(_ s: String) { FileHandle.standardError.write(Data((s + \"\\n\").utf8)) }", "",
       "@main struct TestRunner { static func main() throws {"]
count = 0
for f in files:
    src = open(f).read()
    m = re.search(r"final class (\w+): XCTestCase", src)
    if not m:
        continue
    cls = m.group(1)
    for method, is_async, throws in re.findall(r"func (test\w+)\(\)\s*(async\s+)?(throws)?\s*\{", src):
        if is_async:
            inner = f"try await t.{method}()" if throws else f"await t.{method}()"
            call = ("var __asyncError: (any Error)?; let __sem = DispatchSemaphore(value: 0); "
                    f"Task {{ do {{ {inner} }} catch {{ __asyncError = error }}; __sem.signal() }}; "
                    "__sem.wait(); if let __asyncError { throw __asyncError }")
        else:
            call = f"try t.{method}()" if throws else f"t.{method}()"
        out.append(f"    do {{ let t = {cls}(); try t.setUp(); {call}; try t.tearDown(); report(\"PASS {cls}.{method}\") }}")
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
  -I "$BUILD" -L "$BUILD" -lCodexProtocol -lCodexUtils -lCodexAsyncUtils -lXCTest \
  protocol/tests/suite/*.swift utils/*/tests/suite/*.swift async-utils/tests/suite/*.swift \
  "$RUNNER/runner.swift")

echo "== run"
DYLD_LIBRARY_PATH="$BUILD" "$RUNNER/runner"
