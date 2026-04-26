#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build"
APP="$BUILD/GnomonPoC.app"

echo "=== Gnomon PoC: Sensor + Gamma (Sandboxed) ==="

# Clean
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS"

# Compile
echo "[1/3] Compiling..."
swiftc "$DIR/main.swift" \
    -o "$APP/Contents/MacOS/GnomonPoC" \
    -framework AppKit \
    -framework IOKit \
    -framework CoreGraphics \
    -target arm64-apple-macos15.0 \
    -swift-version 5 \
    -O

# Bundle
echo "[2/3] Bundling..."
cp "$DIR/Info.plist" "$APP/Contents/"

# Sign with sandbox entitlements
echo "[3/3] Signing with App Sandbox..."
codesign --force --sign - --entitlements "$DIR/Entitlements.plist" "$APP"

echo ""
echo "Build OK: $APP"
echo "Entitlements:"
codesign -d --entitlements - "$APP" 2>/dev/null | head -20
echo ""
echo "Launching..."
open "$APP"
