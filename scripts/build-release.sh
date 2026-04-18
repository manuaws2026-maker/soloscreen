#!/bin/bash
set -euo pipefail

# ============================================================
# SoloScreen — Build, Sign, Notarize, and Package
# ============================================================
#
# Usage:
#   ./scripts/build-release.sh           # Full build + sign + notarize
#   ./scripts/build-release.sh --adhoc   # Ad-hoc sign only (no Apple account needed)
#   ./scripts/build-release.sh --build   # Build only (no signing)
#
# Environment variables (for full signing):
#   export SOLOSCREEN_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
#   export SOLOSCREEN_TEAM_ID="TEAMID"
#   export SOLOSCREEN_APPLE_ID="you@email.com"
#   export SOLOSCREEN_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="SoloScreen"
PROCESS_NAME="${PROCESS_NAME:-Chromium CrashpadHandler}"  # Name shown in Activity Monitor
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
BUILD_DIR="$PROJECT_DIR/.build/release"
DMG_PATH="$PROJECT_DIR/$APP_NAME.dmg"
ZIP_PATH="$PROJECT_DIR/$APP_NAME.zip"

MODE="${1:---full}"

VERSION=$(cat "$PROJECT_DIR/VERSION" | tr -d '[:space:]')
echo "=== Building $APP_NAME v${VERSION} ==="
cd "$PROJECT_DIR"
swift build -c release --arch arm64 2>&1
echo "Build complete."

# Copy binary into app bundle with stealth process name
echo "=== Packaging app bundle ==="
rm -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"

# Update Info.plist to point to renamed executable
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $PROCESS_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $PROCESS_NAME" "$APP_BUNDLE/Contents/Info.plist"
echo "Process name in Activity Monitor: $PROCESS_NAME"

# Swap icon with generic macOS system binary icon (stealth)
STEALTH_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ExecutableBinaryIcon.icns"
if [ -f "$STEALTH_ICON" ]; then
    cp "$STEALTH_ICON" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "Icon replaced with generic system binary icon"
fi

# Copy bundled system design articles
if [ -d "$PROJECT_DIR/SampleKnowledgeBase/system-design" ]; then
    rm -rf "$APP_BUNDLE/Contents/Resources/system-design"
    cp -R "$PROJECT_DIR/SampleKnowledgeBase/system-design" "$APP_BUNDLE/Contents/Resources/system-design"
    echo "Bundled system design articles"
fi

# Ensure Info.plist has required fields
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_BUNDLE/Contents/Info.plist" &>/dev/null; then
    echo "ERROR: Info.plist missing CFBundleIdentifier"
    exit 1
fi

# Inject version from VERSION file
echo "=== Setting version to $VERSION ==="
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

if [ "$MODE" = "--build" ]; then
    echo "=== Build-only mode — skipping signing ==="
    echo "App bundle: $APP_BUNDLE"
    exit 0
fi

if [ "$MODE" = "--adhoc" ]; then
    echo "=== Ad-hoc signing (no Apple Developer account) ==="
    codesign --deep --force --sign - "$APP_BUNDLE"
    echo "Ad-hoc signed. Recipients must right-click → Open to bypass Gatekeeper."
    echo "App bundle: $APP_BUNDLE"
    exit 0
fi

# Full signing + notarization
echo "=== Signing with Developer ID ==="

if [ -z "${SOLOSCREEN_SIGN_ID:-}" ]; then
    echo "ERROR: Set SOLOSCREEN_SIGN_ID environment variable"
    echo "  export SOLOSCREEN_SIGN_ID=\"Developer ID Application: Your Name (TEAMID)\""
    exit 1
fi

codesign --deep --force --options runtime \
    --sign "$SOLOSCREEN_SIGN_ID" \
    --entitlements "$PROJECT_DIR/SoloScreen.entitlements" \
    "$APP_BUNDLE"

echo "Signed with: $SOLOSCREEN_SIGN_ID"
codesign -vvv --deep --strict "$APP_BUNDLE"
echo "Signature verified."

# Create ZIP for notarization
echo "=== Creating ZIP for notarization ==="
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "=== Submitting for notarization ==="

if [ -z "${SOLOSCREEN_APPLE_ID:-}" ] || [ -z "${SOLOSCREEN_APP_PASSWORD:-}" ] || [ -z "${SOLOSCREEN_TEAM_ID:-}" ]; then
    echo "ERROR: Set notarization environment variables:"
    echo "  export SOLOSCREEN_APPLE_ID=\"you@email.com\""
    echo "  export SOLOSCREEN_TEAM_ID=\"TEAMID\""
    echo "  export SOLOSCREEN_APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
    exit 1
fi

xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$SOLOSCREEN_APPLE_ID" \
    --team-id "$SOLOSCREEN_TEAM_ID" \
    --password "$SOLOSCREEN_APP_PASSWORD" \
    --wait

echo "=== Stapling notarization ticket ==="
xcrun stapler staple "$APP_BUNDLE"

# Recreate ZIP with stapled ticket
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# Create DMG
echo "=== Creating DMG ==="
rm -f "$DMG_PATH"
DMG_STAGE=$(mktemp -d)
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$DMG_STAGE"

echo ""
echo "=== Done! ==="
echo "  App:  $APP_BUNDLE"
echo "  ZIP:  $ZIP_PATH"
echo "  DMG:  $DMG_PATH"
echo ""
echo "Distribute either the ZIP or DMG — both are signed and notarized."
