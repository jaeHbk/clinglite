#!/usr/bin/env bash
# Run the ClingLite test suite under Command Line Tools (no Xcode).
#
# Why this wrapper exists: CLT does not ship the XCTest Swift module, but it DOES
# ship swift-testing (Testing.framework) under the CLT developer Frameworks dir.
# SwiftPM doesn't add that search path automatically, so we inject it here.
#
# Usage:
#   scripts/test.sh                         # run all tests (debug)
#   scripts/test.sh SomeSuite               # filter by suite/test name (bare name OK)
#   scripts/test.sh -c release SomeSuite    # release build + filter
#   scripts/test.sh --filter SomeSuite      # explicit --filter also works
#
# Convenience: a single trailing bare word (not starting with '-') is treated as a
# --filter argument, so `scripts/test.sh MaskTests` works like `--filter MaskTests`.
set -euo pipefail

FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

cd "$(dirname "$0")/.."

# If exactly one arg is given and it isn't a flag, promote it to `--filter <arg>`.
if [ "$#" -eq 1 ] && [ "${1#-}" = "$1" ]; then
  set -- --filter "$1"
fi

DYLD_FRAMEWORK_PATH="$FW" DYLD_LIBRARY_PATH="$LIB" \
  swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
