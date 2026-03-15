#!/usr/bin/env bash
# build-installer.sh — Builds PluginUpdater.app and packages it as a .pkg installer.
#
# Usage:
#   ./scripts/build-installer.sh [VERSION]
#
# If VERSION is not supplied it is read from project.yml (MARKETING_VERSION).
# The finished installer is written to:
#   build/PluginUpdater-<version>.pkg
#
# Requirements: Xcode command-line tools, xcodegen

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/PluginUpdater"
BUILD_DIR="$REPO_ROOT/build"

APP_NAME="PluginUpdater"
BUNDLE_ID="com.bounceconnection.PluginUpdater"

# Determine version: prefer CLI arg, then project.yml, then default
if [[ ${1:-} != "" ]]; then
    VERSION="$1"
elif command -v grep &>/dev/null && [[ -f "$PROJECT_DIR/project.yml" ]]; then
    VERSION="$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
    VERSION="${VERSION:-1.0.0}"
else
    VERSION="1.0.0"
fi

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
PKG_OUTPUT="$BUILD_DIR/${APP_NAME}-${VERSION}.pkg"

echo "Building $APP_NAME $VERSION installer..."
echo "Output: $PKG_OUTPUT"
echo ""

mkdir -p "$BUILD_DIR"
cd "$PROJECT_DIR"

# ── 1. Generate Xcode project ────────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
    echo "Error: xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi

echo "[1/4] Generating Xcode project..."
"$REPO_ROOT/scripts/generate-version.sh"
xcodegen generate --quiet

# ── 2. Archive ───────────────────────────────────────────────────────────────
echo "[2/4] Archiving (Release build)..."
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    SKIP_INSTALL=NO \
    -quiet

APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: .app not found at expected path: $APP_PATH" >&2
    exit 1
fi

# ── 3. Build .pkg component ──────────────────────────────────────────────────
echo "[3/4] Building .pkg installer..."
pkgbuild \
    --component "$APP_PATH" \
    --install-location "/Applications" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    "$PKG_OUTPUT"

# ── 4. Verify ────────────────────────────────────────────────────────────────
echo "[4/4] Verifying package..."
pkgutil --check-signature "$PKG_OUTPUT" 2>/dev/null || true   # unsigned is fine
pkgutil --payload-files "$PKG_OUTPUT" | head -5

echo ""
echo "Done! Installer: $PKG_OUTPUT"
echo "Size: $(du -sh "$PKG_OUTPUT" | cut -f1)"
