#!/usr/bin/env bash
#
# bundle.sh — Build SubtleAI, create a macOS .app bundle, and ad-hoc sign it.
#
# Usage:
#   ./bundle.sh           Build release and bundle
#   ./bundle.sh clean     Remove build artifacts and the .app bundle
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
APP_NAME="SubtleAI"
BUNDLE_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_NAME="SubtleAI"

# ─── Clean mode ───────────────────────────────────────────────────────
if [[ "${1:-}" == "clean" ]]; then
    echo "Cleaning build artifacts..."
    rm -rf "$PROJECT_DIR/build"
    swift package clean 2>/dev/null || true
    echo "Done."
    exit 0
fi

# ─── Step 1: Build the release binary ────────────────────────────────
echo "==> Building ${APP_NAME} (release)..."
cd "$PROJECT_DIR"
swift build -c release

# Locate the built binary. Swift PM places it under .build/release/.
BUILT_BINARY="$PROJECT_DIR/.build/release/${BINARY_NAME}"
if [[ ! -f "$BUILT_BINARY" ]]; then
    echo "ERROR: Release binary not found at $BUILT_BINARY"
    exit 1
fi
echo "    Binary: $BUILT_BINARY"

# ─── Step 2: Create the .app bundle structure ─────────────────────────
echo "==> Creating app bundle at $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# ─── Step 3: Copy binary ─────────────────────────────────────────────
cp "$BUILT_BINARY" "$MACOS_DIR/${BINARY_NAME}"
chmod +x "$MACOS_DIR/${BINARY_NAME}"

# ─── Step 4: Copy Info.plist ──────────────────────────────────────────
if [[ -f "$PROJECT_DIR/Info.plist" ]]; then
    cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
    echo "    Copied Info.plist"
else
    echo "WARNING: Info.plist not found at $PROJECT_DIR/Info.plist — bundle may not launch correctly."
fi

# ─── Step 5: Copy entitlements (for reference; used during signing) ───
if [[ -f "$PROJECT_DIR/${APP_NAME}.entitlements" ]]; then
    cp "$PROJECT_DIR/${APP_NAME}.entitlements" "$RESOURCES_DIR/${APP_NAME}.entitlements"
    echo "    Copied entitlements"
fi

# ─── Step 6: Copy app icon if it exists ──────────────────────────────
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo "    Copied AppIcon.icns"
fi

# ─── Step 7: Ad-hoc code sign ────────────────────────────────────────
echo "==> Code signing (ad-hoc)..."
ENTITLEMENTS_FLAG=""
if [[ -f "$PROJECT_DIR/${APP_NAME}.entitlements" ]]; then
    ENTITLEMENTS_FLAG="--entitlements $PROJECT_DIR/${APP_NAME}.entitlements"
fi

# shellcheck disable=SC2086
codesign --force --deep --sign - $ENTITLEMENTS_FLAG "$BUNDLE_DIR"
echo "    Signed: $BUNDLE_DIR"

# ─── Step 8: Verify ──────────────────────────────────────────────────
echo "==> Verifying code signature..."
codesign --verify --verbose=2 "$BUNDLE_DIR" 2>&1 || true

# ─── Done ─────────────────────────────────────────────────────────────
BUNDLE_SIZE=$(du -sh "$BUNDLE_DIR" | cut -f1)
echo ""
echo "========================================"
echo "  ${APP_NAME}.app built successfully!"
echo "  Location: $BUNDLE_DIR"
echo "  Size:     $BUNDLE_SIZE"
echo "========================================"
echo ""
echo "To run:  open \"$BUNDLE_DIR\""
echo "To clean: ./bundle.sh clean"
