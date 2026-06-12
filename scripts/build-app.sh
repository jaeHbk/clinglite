#!/usr/bin/env bash
# Assemble ClingLite.app (menu-bar agent) from the SwiftPM build. CLT only — no Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building release binary"
swift build -c release --product ClingApp

APP="ClingLite.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/ClingApp "$APP/Contents/MacOS/ClingLite"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClingLite</string>
  <key>CFBundleDisplayName</key><string>ClingLite</string>
  <key>CFBundleIdentifier</key><string>com.clinglite.app</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>ClingLite</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>ClingLite</string>
</dict>
</plist>
PLIST

# Ad-hoc sign (sufficient for local use).
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(codesign skipped)"

echo "==> Built $APP"
ls -la "$APP/Contents/MacOS"
