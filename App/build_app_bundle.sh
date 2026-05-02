#!/bin/bash
# **ADR-068 Phase 4 + 5** — SPM executable을 .app 번들로 패키징 + DMG 생성.
#
# 사용:
#   ./App/build_app_bundle.sh         # release build + .app 번들
#   ./App/build_app_bundle.sh --dmg   # + DMG 패키지
#
# 결과:
#   - dist/Yuminai.app
#   - dist/Yuminai-1.0.0.dmg  (--dmg 옵션 시)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Yuminai"
APP_VERSION="1.0.0"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "🔨 1. Release build..."
cd "$PROJECT_ROOT"
swift build -c release --product YuminaiApp

BIN_PATH="$PROJECT_ROOT/.build/release/YuminaiApp"
if [ ! -f "$BIN_PATH" ]; then
    echo "❌ Build failed — binary not found at $BIN_PATH"
    exit 1
fi

echo "📦 2. Creating .app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_ROOT/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy app icon
if [ -f "$PROJECT_ROOT/App/Assets/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/App/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "⚠ AppIcon.icns not found — bundling without icon"
fi

# Copy bundled SwiftPM resources (SwiftData model 등)
for bundle in "$PROJECT_ROOT"/.build/release/*.bundle; do
    if [ -d "$bundle" ]; then
        cp -r "$bundle" "$APP_BUNDLE/Contents/Resources/"
    fi
done

echo "✅ App bundle created: $APP_BUNDLE"

# Optional: ad-hoc code sign
echo "🔏 3. Ad-hoc code signing (local run only)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | tail -3 || echo "⚠ codesign failed (continuing)"

# DMG creation if requested
if [ "$1" == "--dmg" ]; then
    echo "💿 4. Creating DMG..."
    DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
    DMG_TEMP="$DIST_DIR/dmg_temp"

    rm -f "$DMG_PATH"
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"

    cp -R "$APP_BUNDLE" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"

    hdiutil create -volname "$APP_NAME $APP_VERSION" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_TEMP"

    echo "✅ DMG created: $DMG_PATH"
    echo "   사용자 설치: DMG 마운트 → Yuminai.app을 Applications 폴더로 드래그"
fi

echo ""
echo "🎉 Done!"
echo "   Run: open $APP_BUNDLE"
echo ""
