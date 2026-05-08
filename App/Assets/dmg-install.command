#!/bin/bash
# **ADR-149** — DMG 자동 설치 스크립트.
#
# 사용자가 DMG 안의 install.command를 더블클릭하면:
# 1. Gatekeeper quarantine 속성 자동 제거 (xattr -cr)
# 2. Yuminai.app을 Applications 폴더로 복사 (없으면)
# 3. 앱 자동 실행
# 4. 결과를 사용자에게 친화적으로 안내
#
# 보안: 사용자가 명시적으로 더블클릭한 경우에만 실행.
# Yuminai 자체는 사용자 데이터에 접근 안 함 (이 스크립트는 단순 설치/실행 helper).

set -e

APP_NAME="Yuminai"
DMG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_APP="$DMG_DIR/$APP_NAME.app"
DEST_APP="/Applications/$APP_NAME.app"

# Terminal 헤더 — 친화적 환영
clear
cat <<EOF

  ┌─────────────────────────────────────────────┐
  │                                             │
  │   ✨  Yuminai 자동 설치를 시작합니다           │
  │                                             │
  └─────────────────────────────────────────────┘

EOF

# 1. DMG에 .app 있는지 확인
if [ ! -d "$SRC_APP" ]; then
    echo "❌ Yuminai.app을 찾을 수 없습니다: $SRC_APP"
    echo "   DMG가 정상적으로 마운트됐는지 확인해 주세요."
    echo ""
    echo "   아무 키나 누르면 종료합니다."
    read -n 1
    exit 1
fi

# 2. /Applications에 복사 (이미 있으면 덮어쓰기)
echo "📦 Step 1/3 — Applications 폴더로 복사 중..."
if [ -d "$DEST_APP" ]; then
    echo "   기존 Yuminai.app 발견 — 덮어쓰기"
fi

# ditto는 권한/속성 보존 + 빠름
ditto "$SRC_APP" "$DEST_APP"
echo "   ✅ 완료: $DEST_APP"
echo ""

# 3. Quarantine 속성 제거 (Gatekeeper 우회)
echo "🔓 Step 2/3 — Gatekeeper 차단 해제 중..."
xattr -cr "$DEST_APP" 2>/dev/null || true
xattr -d com.apple.quarantine "$DEST_APP" 2>/dev/null || true
echo "   ✅ 완료: 첫 실행 시 경고 없음"
echo ""

# 4. 실행
echo "🚀 Step 3/3 — Yuminai 실행 중..."
open "$DEST_APP"
echo "   ✅ 완료"
echo ""

cat <<EOF
  ┌─────────────────────────────────────────────┐
  │                                             │
  │   🎉  설치 완료!                              │
  │                                             │
  │   이제 Dock 또는 Launchpad에서                │
  │   Yuminai를 언제든 실행할 수 있어요.           │
  │                                             │
  └─────────────────────────────────────────────┘

  처음 실행 시 Setup Wizard가 필요한 도구
  (Claude Code 등)의 설치를 안내해 드립니다.

  이 창은 닫아도 됩니다. (3초 후 자동으로 닫힙니다)
EOF

sleep 3
osascript -e 'tell application "Terminal" to close (every window whose name contains "install.command")' 2>/dev/null || true
