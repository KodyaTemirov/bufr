#!/bin/bash
set -euo pipefail

# Build Bufr.app bundle from swift build output
# Usage: ./scripts/build-app.sh [release|debug]

CONFIG="${1:-release}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/$CONFIG"
APP_NAME="Bufr"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
BINARY="$BUILD_DIR/$APP_NAME"

echo "Building $APP_NAME ($CONFIG)..."
swift build -c "$CONFIG" --package-path "$PROJECT_DIR"

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

echo "Assembling $APP_NAME.app bundle..."

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create .app structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/SupportFiles/Info.plist" "$APP_BUNDLE/Contents/"

# Copy icon
if [ -f "$PROJECT_DIR/Sources/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy SPM resource bundle if it exists
RESOURCE_BUNDLE="$BUILD_DIR/Bufr_Bufr.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

# Ad-hoc code sign (no developer certificate needed)
echo "Signing $APP_NAME.app (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Remove quarantine attribute
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "Done! $APP_BUNDLE is ready."
echo "Run: open $APP_BUNDLE"
