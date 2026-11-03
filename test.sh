#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/.build"
mkdir -p "$BUILD_DIR/ModuleCache" "$OUTPUT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"

/usr/bin/xcrun swiftc -sdk "$SDK_PATH" -module-cache-path "$BUILD_DIR/ModuleCache" \
  -parse-as-library -O "$PROJECT_DIR/Source/SessionEngine.swift" \
  "$PROJECT_DIR/Tests/SessionEngineTests.swift" -o "$BUILD_DIR/SessionEngineTests"
"$BUILD_DIR/SessionEngineTests"

/usr/bin/xcrun swiftc -sdk "$SDK_PATH" -module-cache-path "$BUILD_DIR/ModuleCache" \
  -parse-as-library -O "$PROJECT_DIR/Source/AutoResumeGate.swift" \
  "$PROJECT_DIR/Tests/AutoResumeGateTests.swift" -o "$BUILD_DIR/AutoResumeGateTests"
"$BUILD_DIR/AutoResumeGateTests"

if [ "${RUN_UI_TESTS:-0}" = "1" ]; then
  APP_EXECUTABLE="$OUTPUT_DIR/Fore2Break.app/Contents/MacOS/Fore2Break"
  if [ ! -x "$APP_EXECUTABLE" ]; then
    echo "Build the app with ./build.sh before running UI integration tests." >&2
    exit 1
  fi
  "$APP_EXECUTABLE" --integration-test
fi
