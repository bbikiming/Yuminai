#!/bin/bash
# **ADR-068 + ADR-069** — SPM executable을 .app 번들로 패키징 + DMG 생성.
#
# 사용:
#   ./App/build_app_bundle.sh                     # native arch only
#   ./App/build_app_bundle.sh --universal         # arm64 + x86_64 (ADR-069 Phase 1)
#   ./App/build_app_bundle.sh --dmg               # + DMG (basic)
#   ./App/build_app_bundle.sh --dmg --custom-dmg  # + custom DMG with bg image (ADR-069 Phase 3)
#   ./App/build_app_bundle.sh --universal --dmg --custom-dmg  # 모두

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Yuminai"
APP_VERSION="1.1.1"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

# Parse args
UNIVERSAL=false
DMG=false
CUSTOM_DMG=false
for arg in "$@"; do
    case $arg in
        --universal) UNIVERSAL=true ;;
        --dmg) DMG=true ;;
        --custom-dmg) CUSTOM_DMG=true ;;
    esac
done

# ADR-069 Phase 1 — Universal binary (arm64 + x86_64)
if [ "$UNIVERSAL" = true ]; then
    echo "🔨 1. Universal release build (arm64 + x86_64)..."
    cd "$PROJECT_ROOT"
    swift build -c release --product YuminaiApp --arch arm64 --arch x86_64
    BIN_PATH="$PROJECT_ROOT/.build/apple/Products/Release/YuminaiApp"
    if [ ! -f "$BIN_PATH" ]; then
        # fallback: try standard release path
        BIN_PATH="$PROJECT_ROOT/.build/release/YuminaiApp"
    fi
else
    echo "🔨 1. Native release build..."
    cd "$PROJECT_ROOT"
    swift build -c release --product YuminaiApp
    BIN_PATH="$PROJECT_ROOT/.build/release/YuminaiApp"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "❌ Build failed — binary not found at $BIN_PATH"
    exit 1
fi

# Verify architecture
echo "📐 Binary architecture:"
file "$BIN_PATH"

echo "📦 2. Creating .app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary (Info.plist의 CFBundleExecutable과 일치하는 이름으로)
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_ROOT/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy app icon
if [ -f "$PROJECT_ROOT/App/Assets/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/App/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "⚠ AppIcon.icns not found"
fi

# Copy SwiftPM bundles (resources)
for bundle in "$PROJECT_ROOT"/.build/release/*.bundle; do
    if [ -d "$bundle" ]; then
        cp -r "$bundle" "$APP_BUNDLE/Contents/Resources/"
    fi
done

echo "✅ App bundle created: $APP_BUNDLE"

echo "🔏 3. Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | tail -3 || echo "⚠ codesign failed"

# DMG creation
if [ "$DMG" = true ]; then
    echo "💿 4. Creating DMG..."
    DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
    DMG_TEMP="$DIST_DIR/dmg_temp"

    rm -f "$DMG_PATH"
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"

    cp -R "$APP_BUNDLE" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"

    if [ "$CUSTOM_DMG" = true ]; then
        # ADR-069 Phase 3 / ADR-149 — Custom DMG: bg + install.command + README
        echo "🎨 4a. Building custom DMG layout..."

        # SVG → PNG 자동 변환 (rsvg-convert)
        BG_SVG="$PROJECT_ROOT/App/Assets/dmg-background.svg"
        BG_IMG="$PROJECT_ROOT/App/Assets/dmg-background.png"
        if command -v rsvg-convert >/dev/null 2>&1 && [ -f "$BG_SVG" ]; then
            echo "   🖼  SVG → PNG (800×500)..."
            rsvg-convert -w 800 -h 500 "$BG_SVG" -o "$BG_IMG" 2>/dev/null || true
        fi

        if [ -f "$BG_IMG" ]; then
            mkdir -p "$DMG_TEMP/.background"
            cp "$BG_IMG" "$DMG_TEMP/.background/background.png"
        fi

        # ADR-149 — install.command + README 동봉
        INSTALL_CMD_SRC="$PROJECT_ROOT/App/Assets/dmg-install.command"
        README_SRC="$PROJECT_ROOT/App/Assets/dmg-readme.txt"
        if [ -f "$INSTALL_CMD_SRC" ]; then
            cp "$INSTALL_CMD_SRC" "$DMG_TEMP/install.command"
            chmod +x "$DMG_TEMP/install.command"
            echo "   ⚡ install.command 동봉 (자동 설치 + Gatekeeper 우회)"
        fi
        if [ -f "$README_SRC" ]; then
            cp "$README_SRC" "$DMG_TEMP/README.txt"
            echo "   📄 README.txt 동봉 (한국어 가이드)"
        fi

        # Create RW DMG first
        DMG_RW="$DIST_DIR/${APP_NAME}_rw.dmg"
        rm -f "$DMG_RW"
        hdiutil create -volname "$APP_NAME $APP_VERSION" \
            -srcfolder "$DMG_TEMP" \
            -ov -format UDRW -fs HFS+ \
            "$DMG_RW"

        # Mount + apply AppleScript layout
        MOUNT_DIR=$(hdiutil attach "$DMG_RW" | grep "Volumes" | awk '{print $3}')
        if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
            sleep 1
            osascript <<EOF || echo "⚠ AppleScript layout 적용 실패 (DMG는 그대로 진행)"
tell application "Finder"
    tell disk "$APP_NAME $APP_VERSION"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 100, 1000, 600}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 88
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        try
            set position of item "install.command" of container window to {150, 380}
        end try
        try
            set position of item "README.txt" of container window to {450, 380}
        end try
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
            sync
            sleep 2
            hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
            sleep 2
        fi

        # ADR-149 — convert "Resource temporarily unavailable" 방지:
        # 1. 추가로 모든 mount 강제 해제 (volume name 기준)
        # 2. retry 3회 with backoff
        # 3. 최후엔 RW DMG 그대로 사용 (사용자 정상 작동)
        for vol in /Volumes/"$APP_NAME "*; do
            [ -d "$vol" ] && hdiutil detach "$vol" -force 2>/dev/null || true
        done
        sleep 2

        CONVERT_OK=false
        for attempt in 1 2 3; do
            if hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH" 2>&1; then
                CONVERT_OK=true
                break
            fi
            echo "   ⏳ convert 재시도 $attempt/3 (5초 대기)..."
            sleep 5
        done

        if [ "$CONVERT_OK" = true ]; then
            rm -f "$DMG_RW"
        else
            echo "   ⚠ UDZO 압축 실패 — RW DMG를 release용으로 rename"
            mv "$DMG_RW" "$DMG_PATH"
        fi
    else
        # Standard UDZO compressed DMG
        hdiutil create -volname "$APP_NAME $APP_VERSION" \
            -srcfolder "$DMG_TEMP" \
            -ov -format UDZO \
            "$DMG_PATH"
    fi

    rm -rf "$DMG_TEMP"

    echo "✅ DMG created: $DMG_PATH"
    echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"
fi

echo ""
echo "🎉 Done!"
echo "   Run:     open $APP_BUNDLE"
echo "   Install: cp -R $APP_BUNDLE /Applications/"
echo ""
