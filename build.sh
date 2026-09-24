#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "Bygger PictureApp (release)…"
swift build -c release

APP_NAME="PictureApp"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Sources/PictureApp/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc-signera så appen får en stabil identitet och kan begära
# Foton-behörighet korrekt (kräver ingen betald utvecklarlicens).
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Klart! Öppna appen med:"
echo "  open $APP_BUNDLE"
