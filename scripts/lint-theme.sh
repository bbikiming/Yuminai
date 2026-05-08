#!/bin/bash
# **ADR-147** — SwiftUI 테마 lint script.
#
# 목적: Theme.swift / SharedComponents.swift에서 정의된 토큰을 사용하지 않고
# 하드코딩된 color literal / corner radius / padding 숫자를 감지한다.
#
# 사용:
#   ./scripts/lint-theme.sh           # 전체 검사 (0=pass, 1=violations)
#   ./scripts/lint-theme.sh --warn    # 위반 시 exit 0 (경고만, CI 비차단용)
#
# CI 통합: .github/workflows/release.yml에서 "swift test" 전 실행
#
# 예외 파일 (정의처 — 검사 제외):
#   Sources/YuminaiUI/Theme.swift
#   Sources/YuminaiUI/SharedComponents.swift
#   Sources/YuminaiUI/PolishedComponents.swift
#   Sources/YuminaiUI/FlatComponents.swift
#   Sources/YuminaiUI/SheetFrame.swift
#   Sources/YuminaiUI/CategoryColors.swift

set -euo pipefail

WARN_ONLY=0
if [[ "${1:-}" == "--warn" ]]; then
    WARN_ONLY=1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Sources"

# ---- 예외 파일 (정의처) ----
EXCLUDE_FILES=(
    "Theme.swift"
    "SharedComponents.swift"
    "PolishedComponents.swift"
    "FlatComponents.swift"
    "SheetFrame.swift"
    "CategoryColors.swift"
    "AutoRunCommandExtractor.swift"
)

# ---- grep 파일 목록 구성 (예외 제외) ----
SWIFT_FILES=()
while IFS= read -r -d '' file; do
    skip=0
    for excl in "${EXCLUDE_FILES[@]}"; do
        if [[ "$(basename "$file")" == "$excl" ]]; then
            skip=1
            break
        fi
    done
    if [[ $skip -eq 0 ]]; then
        SWIFT_FILES+=("$file")
    fi
done < <(find "$SRC" -name "*.swift" -print0)

TOTAL_VIOLATIONS=0

echo "🔍 Theme lint 시작 (파일 ${#SWIFT_FILES[@]}개)"
echo "=============================="

# ---- 1. Color literal — 허용 목록 외 직접 사용 ----
#
# 허용: Color.clear, Color.white, Color.black, Color.primary, Color.secondary,
#       Color.accentColor (SwiftUI 시스템 색)
# 차단: Color.orange, Color.red, Color.green, Color.blue, Color.yellow,
#       Color.purple, Color.pink, Color.teal
#
BLOCKED_COLORS="Color\.(orange|red|green|blue|yellow|purple|pink|teal)\b"
ALLOWED_COLORS="(Color\.clear|Color\.white|Color\.black|Color\.primary|Color\.secondary|Color\.accentColor)"

COLOR_VIOLATIONS=0
for file in "${SWIFT_FILES[@]}"; do
    # grep으로 차단 색상 검색, 허용 색상 제외
    while IFS= read -r line; do
        lineno=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)
        # 주석 줄 제외
        trimmed="${content#"${content%%[![:space:]]*}"}"
        if [[ "$trimmed" == //* ]]; then continue; fi
        echo "  ❌ COLOR: $(basename "$file"):$lineno → $content"
        ((COLOR_VIOLATIONS++)) || true
    done < <(grep -nE "$BLOCKED_COLORS" "$file" 2>/dev/null | grep -vE "$ALLOWED_COLORS" || true)
done

if [[ $COLOR_VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "💡 수정 방법: Color.<name> → Theme.Color.<semantic_token>"
    echo "   예: Color.orange → Theme.Color.warningStrong"
    echo "   예: Color.green  → Theme.Color.gitAdded 또는 Theme.Color.success"
    echo "   예: Color.red    → Theme.Color.gitRemoved 또는 Theme.Color.danger"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + COLOR_VIOLATIONS))
fi

echo ""
echo "  Color violations: $COLOR_VIOLATIONS"

# ---- 2. 하드코딩된 .cornerRadius(<숫자>) ----
RADIUS_VIOLATIONS=0
for file in "${SWIFT_FILES[@]}"; do
    while IFS= read -r line; do
        lineno=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)
        trimmed="${content#"${content%%[![:space:]]*}"}"
        if [[ "$trimmed" == //* ]]; then continue; fi
        echo "  ❌ RADIUS: $(basename "$file"):$lineno → $content"
        ((RADIUS_VIOLATIONS++)) || true
    done < <(grep -nE "\.cornerRadius\([0-9]+(\.[0-9]+)?\)" "$file" 2>/dev/null || true)
done

if [[ $RADIUS_VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "💡 수정 방법: .cornerRadius(<n>) → .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.<token>))"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + RADIUS_VIOLATIONS))
fi

echo "  Radius violations: $RADIUS_VIOLATIONS"

# ---- 3. 하드코딩된 .padding(<숫자>) (허용: 0, 1, 2는 조정값으로 허용) ----
PADDING_VIOLATIONS=0
for file in "${SWIFT_FILES[@]}"; do
    while IFS= read -r line; do
        lineno=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)
        trimmed="${content#"${content%%[![:space:]]*}"}"
        if [[ "$trimmed" == //* ]]; then continue; fi
        # 0, 1, 2 허용 (미세 조정값)
        val=$(echo "$content" | grep -oE "\.padding\([0-9]+(\.[0-9]+)?" | grep -oE "[0-9]+(\.[0-9]+)?$" || true)
        if [[ -z "$val" ]]; then continue; fi
        # 0, 1, 2는 예외
        if [[ "$val" == "0" || "$val" == "1" || "$val" == "2" || "$val" == "0.5" || "$val" == "1.5" ]]; then continue; fi
        echo "  ❌ PADDING: $(basename "$file"):$lineno → $content"
        ((PADDING_VIOLATIONS++)) || true
    done < <(grep -nE "\.padding\([0-9]{2,}(\.[0-9]+)?\)" "$file" 2>/dev/null || true)
done

if [[ $PADDING_VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "💡 수정 방법: .padding(<n>) → .padding(Theme.Spacing.<xs|sm|md|lg|xl|xxl>)"
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + PADDING_VIOLATIONS))
fi

echo "  Padding violations: $PADDING_VIOLATIONS"

echo ""
echo "=============================="
echo "총 위반: $TOTAL_VIOLATIONS"

if [[ $TOTAL_VIOLATIONS -gt 0 ]]; then
    if [[ $WARN_ONLY -eq 1 ]]; then
        echo "⚠️  위반 있음 (--warn 모드: exit 0)"
        exit 0
    else
        echo "❌ Lint 실패"
        exit 1
    fi
else
    echo "✅ Theme lint 통과"
    exit 0
fi
