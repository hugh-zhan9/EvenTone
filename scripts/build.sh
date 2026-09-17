#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
bundle="$PWD/dist/EvenTone.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/EvenTone" "$bundle/Contents/MacOS/EvenTone"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/.build/EvenTone.iconset"
iconutil -c icns "$PWD/.build/EvenTone.iconset" -o "$bundle/Contents/Resources/EvenTone.icns"
plutil -lint "$bundle/Contents/Info.plist"
# Local demo signature. A Developer ID identity can be supplied for a stable signing identity.
codesign --force --sign "${EVENTONE_SIGN_IDENTITY:--}" --identifier local.eventone.app "$bundle"
codesign --verify --strict "$bundle"
printf 'Built: %s\nRun: open "%s"\n' "$bundle" "$bundle"
