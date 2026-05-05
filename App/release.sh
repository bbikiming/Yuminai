#!/bin/bash
# **ADR-123** — 로컬 release helper.
#
# 사용:
#   ./App/release.sh                  # 인터랙티브 (버전 입력 받음)
#   ./App/release.sh 1.2.0            # 직접 버전 지정
#   ./App/release.sh 1.2.0 --notes "릴리스 메모"
#
# 동작:
# 1. 작업 디렉토리 clean 확인
# 2. 빌드 + 테스트 (회귀 0 확인)
# 3. App/build_app_bundle.sh로 DMG 생성
# 4. git tag 생성 (annotated)
# 5. tag push → GitHub Actions release.yml 자동 트리거 (있으면)
# 6. 또는 gh CLI로 직접 release 생성 + DMG 업로드 (로컬 즉시 배포)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# ---- Args ----
VERSION="$1"
NOTES="$2"

# ---- Pre-flight ----
echo "🔍 Pre-flight 검사..."

# 1. git 저장소인지
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ git 저장소가 아닙니다."
    exit 1
fi

# 2. clean working tree
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "⚠️  커밋되지 않은 변경 사항이 있습니다:"
    git status --short
    read -p "그래도 진행할까요? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "취소됨."
        exit 1
    fi
fi

# 3. 버전 입력
if [ -z "$VERSION" ]; then
    LATEST=$(git tag --list 'v*.*.*' --sort=-v:refname | head -1)
    echo "📌 마지막 버전: ${LATEST:-(없음)}"
    read -p "🆕 새 버전 (예: 1.2.0): " VERSION
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ 버전 형식 오류 — semantic version (예: 1.2.0)"
    exit 1
fi

TAG="v$VERSION"

# 4. 이미 존재하는 태그인지
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ 태그 $TAG 이미 존재합니다."
    exit 1
fi

# ---- Build ----
echo ""
echo "🔨 빌드 + 테스트..."
swift build -c release --product YuminaiApp
swift test --parallel 2>&1 | tail -3

# ---- Update version in build_app_bundle.sh ----
echo ""
echo "📝 build_app_bundle.sh 버전 갱신..."
sed -i.bak "s/^APP_VERSION=.*/APP_VERSION=\"$VERSION\"/" App/build_app_bundle.sh
rm -f App/build_app_bundle.sh.bak

# ---- DMG ----
echo ""
echo "💿 DMG 생성..."
./App/build_app_bundle.sh --dmg 2>&1 | tail -5

DMG_PATH="dist/Yuminai-$VERSION.dmg"
if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG 생성 실패: $DMG_PATH 없음"
    exit 1
fi

DMG_SIZE=$(ls -lah "$DMG_PATH" | awk '{print $5}')
echo "✅ DMG 준비됨: $DMG_PATH ($DMG_SIZE)"

# ---- Notes ----
if [ -z "$NOTES" ]; then
    LAST_TAG=$(git tag --list 'v*.*.*' --sort=-v:refname | head -1)
    if [ -n "$LAST_TAG" ]; then
        NOTES=$(git log "$LAST_TAG..HEAD" --pretty=format:"- %s" 2>/dev/null | head -20)
    else
        NOTES=$(git log -10 --pretty=format:"- %s")
    fi
fi

# ---- Tag + commit version bump ----
echo ""
echo "🏷  Git tag 생성: $TAG"
if ! git diff --quiet App/build_app_bundle.sh; then
    git add App/build_app_bundle.sh
    git commit -m "chore: bump version to $VERSION"
fi
git tag -a "$TAG" -m "Yuminai $VERSION

$NOTES"
echo "✅ 태그 $TAG 생성됨"

# ---- Push or GitHub Release ----
echo ""
echo "📤 배포 옵션:"
echo "  [1] git push origin $TAG → GitHub Actions가 자동 release (.github/workflows/release.yml 필요)"
echo "  [2] gh CLI로 즉시 release 생성 + DMG 업로드 (로컬에서 직접)"
echo "  [3] 종료 (수동 처리)"
read -p "선택 (1/2/3): " -n 1 -r CHOICE
echo

case "$CHOICE" in
    1)
        echo "🚀 git push..."
        git push origin "$TAG"
        echo "✅ 태그 push 완료. GitHub Actions에서 빌드 + release 진행 중일 거예요."
        echo "   확인: https://github.com/<your-org>/Yuminai/actions"
        ;;
    2)
        if ! command -v gh >/dev/null 2>&1; then
            echo "❌ gh CLI 미설치. brew install gh 후 다시 시도하세요."
            exit 1
        fi
        echo "🚀 gh release create..."
        git push origin "$TAG"
        gh release create "$TAG" "$DMG_PATH" \
            --title "Yuminai $VERSION" \
            --notes "$NOTES

## 설치 방법

1. **$DMG_PATH** 다운로드
2. DMG 더블클릭 → Yuminai.app을 Applications 폴더로 드래그
3. 첫 실행 시 우클릭 → 열기 → 열기 (확인되지 않은 개발자 우회)
4. Setup Wizard가 Claude Code / Codex CLI 설치를 안내합니다"
        echo "✅ Release 생성 완료"
        ;;
    *)
        echo "ℹ️  태그만 생성됨 ($TAG). 수동으로 push + release 진행하세요:"
        echo "    git push origin $TAG"
        echo "    gh release create $TAG $DMG_PATH"
        ;;
esac
