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
#   6. Sparkle EdDSA signing key saved in the login Keychain as account "gnomon"
#
# Usage: ./Scripts/release.sh [version]
#   version: must match MARKETING_VERSION in project.yml

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
TEAM_ID="${GNOMON_TEAM_ID:-GA2LMK5XL2}"
SIGNING_IDENTITY="${GNOMON_SIGNING_IDENTITY:-Developer ID Application: sunguk park (GA2LMK5XL2)}"
NOTARY_PROFILE="${GNOMON_NOTARY_PROFILE:-gnomon-notary}"
GITHUB_REPO="sunpark20/gnomon"
SPARKLE_VERSION="2.9.4"
SPARKLE_SHA256="ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"
SPARKLE_ACCOUNT="gnomon"

# ── Version ────────────────────────────────────────────────────────
PROJECT_VERSION=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9.]+)"?$/\1/p' project.yml | head -1)
VERSION="${1:-$PROJECT_VERSION}"
if [ "$VERSION" != "$PROJECT_VERSION" ]; then
    echo -e "${RED}Version ${VERSION} must match MARKETING_VERSION ${PROJECT_VERSION}.${NC}"
    exit 1
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
command -v xcodegen >/dev/null || { echo -e "${RED}xcodegen not found. Install: brew install xcodegen${NC}"; exit 1; }
command -v python3 >/dev/null || { echo -e "${RED}python3 not found.${NC}"; exit 1; }

TAG="v${VERSION}"
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo -e "${RED}Release ${TAG} already exists.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}▶ Generating Xcode project${NC}"
xcodegen generate

# ── Gate ───────────────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Running gate checks${NC}"
./Scripts/gate.sh --skip-tests

# ── Archive ────────────────────────────────────────────────────────
ARCHIVE_PATH="build/Gnomon.xcarchive"
APP_PATH="build/Gnomon.app"
DMG_PATH="build/Gnomon-${VERSION}.dmg"
APPCAST_PATH="build/appcast.xml"
SPARKLE_ROOT="build/sparkle-tools"
SIGN_UPDATE="${SPARKLE_ROOT}/bin/sign_update"
mkdir -p build
rm -rf "$ARCHIVE_PATH" "$APP_PATH" "$DMG_PATH" "$APPCAST_PATH"

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

# ── Sparkle feed ───────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Preparing signed Sparkle feed${NC}"
mkdir -p "$SPARKLE_ROOT"
curl -fsSL \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    -o build/Sparkle.tar.xz
echo "${SPARKLE_SHA256}  build/Sparkle.tar.xz" | shasum -a 256 -c -
tar -xf build/Sparkle.tar.xz -C "$SPARKLE_ROOT" ./bin/generate_keys ./bin/sign_update

EXPECTED_PUBLIC_KEY="$("${SPARKLE_ROOT}/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p)"
if [ -z "$EXPECTED_PUBLIC_KEY" ]; then
    echo -e "${RED}No Sparkle signing key is available for account ${SPARKLE_ACCOUNT}.${NC}"
    exit 1
fi
EMBEDDED_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_PATH/Contents/Info.plist")"
if [ "$EXPECTED_PUBLIC_KEY" != "$EMBEDDED_PUBLIC_KEY" ]; then
    echo -e "${RED}The app's Sparkle public key does not match the signing key in Keychain.${NC}"
    exit 1
fi

UPDATE_SIGNATURE="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" -p "$DMG_PATH")"
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$DMG_PATH" "$UPDATE_SIGNATURE"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
python3 scripts/create_appcast.py \
    --version "$TAG" \
    --build-number "$BUILD_NUMBER" \
    --asset "$DMG_PATH" \
    --signature "$UPDATE_SIGNATURE" \
    --output "$APPCAST_PATH"
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$APPCAST_PATH"
"$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" --verify "$APPCAST_PATH"
python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$APPCAST_PATH"

# ── GitHub Release ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▶ Creating draft GitHub release${NC}"
gh release create "$TAG" "$DMG_PATH" \
    --repo "$GITHUB_REPO" \
    --title "Gnomon v${VERSION}" \
    --generate-notes \
    --draft

gh release upload "$TAG" "$APPCAST_PATH" --repo "$GITHUB_REPO" --clobber
RELEASE_ID="$(gh api "repos/${GITHUB_REPO}/releases/tags/${TAG}" --jq .id)"
gh api --method PATCH "repos/${GITHUB_REPO}/releases/${RELEASE_ID}" -F draft=false >/dev/null

echo -e "\n${GREEN}✓ Released Gnomon v${VERSION}${NC}"
