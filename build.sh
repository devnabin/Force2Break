#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Fore2Break"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
STAGING_APP="$BUILD_DIR/$APP_NAME.app"
BREAK_SOUND="$PROJECT_DIR/Resources/BreakComplete.mp3"

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple Command Line Tools are required. Install them with: xcode-select --install" >&2
  exit 1
fi

if [ ! -s "$BREAK_SOUND" ]; then
  echo "The bundled break-completion sound is missing or empty: $BREAK_SOUND" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR/ModuleCache" "$OUTPUT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
SWIFT_FLAGS=(-sdk "$SDK_PATH" -module-cache-path "$BUILD_DIR/ModuleCache" -parse-as-library -O)
SOURCES=("$PROJECT_DIR"/Source/*.swift)
if [ ! -f "${SOURCES[0]}" ]; then
  echo "No Swift source files found in $PROJECT_DIR/Source." >&2
  exit 1
fi

echo "Building the Apple silicon application…"
/usr/bin/xcrun swiftc "${SWIFT_FLAGS[@]}" -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework ServiceManagement -framework IOKit -framework CoreAudio -framework CoreMediaIO \
  "${SOURCES[@]}" -o "$BUILD_DIR/$APP_NAME-arm64"

echo "Building Intel support…"
if /usr/bin/xcrun swiftc "${SWIFT_FLAGS[@]}" -target x86_64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework ServiceManagement -framework IOKit -framework CoreAudio -framework CoreMediaIO \
  "${SOURCES[@]}" -o "$BUILD_DIR/$APP_NAME-x86_64" \
  2>"$BUILD_DIR/intel-build.log"; then
  /usr/bin/xcrun lipo -create "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64" \
    -output "$BUILD_DIR/$APP_NAME"
  echo "Created a universal application for Apple silicon and Intel Macs."
else
  /bin/cp "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME"
  echo "Intel compilation was unavailable; built for Apple silicon only." >&2
  echo "Compiler details: $BUILD_DIR/intel-build.log" >&2
fi

echo "Drawing the application icon…"
/usr/bin/xcrun swiftc -sdk "$SDK_PATH" -module-cache-path "$BUILD_DIR/ModuleCache" \
  -framework AppKit "$PROJECT_DIR/Tools/GenerateIcon.swift" -o "$BUILD_DIR/GenerateIcon"
"$BUILD_DIR/GenerateIcon" "$BUILD_DIR/$APP_NAME.iconset" "$BUILD_DIR/$APP_NAME.icns"
if /usr/bin/iconutil -c icns "$BUILD_DIR/$APP_NAME.iconset" -o "$BUILD_DIR/$APP_NAME-iconutil.icns" \
  2>"$BUILD_DIR/iconutil.log"; then
  /bin/cp "$BUILD_DIR/$APP_NAME-iconutil.icns" "$BUILD_DIR/$APP_NAME.icns"
else
  echo "Using the icon generator's native ICNS container (iconutil is unavailable)."
fi

if [ -d "$STAGING_APP" ]; then
  /bin/rm -rf "$STAGING_APP"
fi
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
/bin/cp "$BUILD_DIR/$APP_NAME" "$STAGING_APP/Contents/MacOS/$APP_NAME"
/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$STAGING_APP/Contents/Info.plist"
/bin/cp "$BUILD_DIR/$APP_NAME.icns" "$STAGING_APP/Contents/Resources/$APP_NAME.icns"
/bin/cp "$BREAK_SOUND" "$STAGING_APP/Contents/Resources/BreakComplete.mp3"
/bin/chmod +x "$STAGING_APP/Contents/MacOS/$APP_NAME"
/usr/bin/plutil -lint "$STAGING_APP/Contents/Info.plist"
# Finder and file-provider metadata can be inherited by generated bundles.
# Clear only this staged app before signing so its resources are sealable.
/usr/bin/xattr -cr "$STAGING_APP"
/usr/bin/codesign --force --sign - "$STAGING_APP"
/usr/bin/codesign --verify --strict "$STAGING_APP"

# Archive from the verified stage, omitting metadata added by cloud folders.
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "$STAGING_APP" "$OUTPUT_DIR/$APP_NAME.zip"
VERIFY_DIR="$(/usr/bin/mktemp -d /private/tmp/Fore2Break-verify.XXXXXX)"
trap '/bin/rm -rf "$VERIFY_DIR"' EXIT
/usr/bin/ditto -x -k "$OUTPUT_DIR/$APP_NAME.zip" "$VERIFY_DIR"
/usr/bin/codesign --verify --strict "$VERIFY_DIR/$APP_NAME.app"

if [ -d "$APP_PATH" ]; then
  /bin/rm -rf "$APP_PATH"
fi
/bin/mv "$STAGING_APP" "$APP_PATH"
# Finder or a file provider can attach metadata again after this cleanup.
# The exact archive contents were verified above outside that provider.
/usr/bin/xattr -cr "$APP_PATH"
echo "Ready: $APP_PATH"
echo "Archive: $OUTPUT_DIR/$APP_NAME.zip"
