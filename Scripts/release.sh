#!/usr/bin/env bash
# Gnomon release pipeline
# Developer ID signing + Notarization + DMG creation + GitHub Release
#
# Prerequisites:
#   1. Apple Developer Program membership ($99/yr)
#   2. "Developer ID Application" certificate installed in Keychain
#   3. App-specific password stored in Keychain:
#      xcrun notarytool store-credentials "gnomon-notary" \
#        --apple-id "YOUR_APPLE_ID" \
#        --team-id "YOUR_TEAM_ID" \
#        --password "YOUR_APP_SPECIFIC_PASSWORD"
#   4. create-dmg installed: brew install create-dmg
#   5. gh CLI installed and authenticated: brew install gh
#
# Usage: ./Scripts/release.sh [version]
#   version: e.g. "1.4.0" (defaults to MARKETING_VERSION in project.yml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Configuration ──────────────────────────────────────────────────
# TODO: Fill these in after joining Apple Developer Program
TEAM_ID="${GNOMON_TEAM_ID:-GA2LMK5XL2}"
SIGNING_IDENTITY="${GNOMON_SIGNING_IDENTITY:-Developer ID Application: sunguk park (GA2LMK5XL2)}"
NOTARY_PROFILE="${GNOMON_NOTARY_PROFILE:-gnomon-notary}"
GITHUB_REPO="sunpark20/gnomon"

# ── Version ────────────────────────────────────────────────────────
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*: *"\?\([0-9.]*\)"\?/\1/')
fi
echo -e "${YELLOW}Building Gnomon v${VERSION}${NC}"

# ── Preflight ──────────────────────────────────────────────────────
if [ -z "$TEAM_ID" ]; then
    echo -e "${RED}Error: Set GNOMON_TEAM_ID environment variable${NC}"
    echo "  export GNOMON_TEAM_ID=\"YOUR_10_CHAR_TEAM_ID\""
    exit 1
fi

command -v create-dmg >/dev/null || { echo -e "${RED}create-dmg not found. Install: brew install create-dmg${NC}"; exit 1; }
command -v gh >/dev/null || { echo -e "${RED}gh not found. Install: brew install gh${NC}"; exit 1; }
command -v xcrun >/dev/null || { echo -e "${RED}xcrun not found. Install Xcode Command Line Tools.${NC}"; exit 1; }

# ── Gate ───────────────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Running gate checks${NC}"
./Scripts/gate.sh

# ── Archive ────────────────────────────────────────────────────────
ARCHIVE_PATH="build/Gnomon.xcarchive"
APP_PATH="build/Gnomon.app"
DMG_PATH="build/Gnomon-${VERSION}.dmg"

echo -e "\n${YELLOW}▶ Archiving${NC}"
xcodebuild archive \
    -project Gnomon.xcodeproj \
    -scheme Gnomon \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    -quiet

# ── Export ─────────────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Exporting app${NC}"
cat > build/export-options.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath build/ \
    -exportOptionsPlist build/export-options.plist \
    -quiet

# ── Notarize ───────────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Notarizing${NC}"
ditto -c -k --keepParent "$APP_PATH" build/Gnomon.zip
xcrun notarytool submit build/Gnomon.zip \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo -e "\n${YELLOW}▶ Stapling${NC}"
xcrun stapler staple "$APP_PATH"

# ── DMG ────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Creating DMG${NC}"
rm -f "$DMG_PATH"
create-dmg \
    --volname "Gnomon ${VERSION}" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Gnomon.app" 175 190 \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

# Sign the DMG too
codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo -e "\n${GREEN}✓ DMG ready: ${DMG_PATH}${NC}"

# ── GitHub Release ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Creating GitHub release${NC}"
gh release create "v${VERSION}" "$DMG_PATH" \
    --repo "$GITHUB_REPO" \
    --title "Gnomon v${VERSION}" \
    --generate-notes

echo -e "\n${GREEN}✓ Released Gnomon v${VERSION}${NC}"
