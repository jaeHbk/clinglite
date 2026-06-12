#!/usr/bin/env bash
# Run the ClingLite test suite under Command Line Tools (no Xcode).
#
# Why this wrapper exists: CLT does not ship the XCTest Swift module, but it DOES
# ship swift-testing (Testing.framework) under the CLT developer Frameworks dir.
# SwiftPM doesn't add that search path automatically, so we inject it here.
#
# Usage:
#   scripts/test.sh                         # run all tests (debug)
#   scripts/test.sh SomeSuite               # filter by suite/test name
#   scripts/test.sh -c release SomeSuite    # release build + filter
set -euo pipefail

FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

cd "$(dirname "$0")/.."

DYLD_FRAMEWORK_PATH="$FW" DYLD_LIBRARY_PATH="$LIB" \
  swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
